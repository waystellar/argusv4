"""
Stripe Subscription API routes - Premium tier access management.

Implements the monetization strategy from Product Vision:
- Free tier: Public telemetry and streams
- Premium tier: Enhanced telemetry, priority support

Dependencies:
    pip install stripe

Environment variables:
    STRIPE_SECRET_KEY: Your Stripe secret key
    STRIPE_WEBHOOK_SECRET: Webhook signing secret
    STRIPE_PRICE_ID: Price ID for premium subscription
"""
import os
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Header, Request
from pydantic import BaseModel, EmailStr
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.models import Base
from app.config import get_settings

settings = get_settings()
router = APIRouter(prefix="/api/v1/subscriptions", tags=["subscriptions"])

# Stripe configuration (loaded from environment)
STRIPE_SECRET_KEY = os.environ.get("STRIPE_SECRET_KEY", "")
STRIPE_WEBHOOK_SECRET = os.environ.get("STRIPE_WEBHOOK_SECRET", "")
STRIPE_PRICE_ID = os.environ.get("STRIPE_PRICE_ID", "price_premium_monthly")

# Try to import Stripe
try:
    import stripe
    stripe.api_key = STRIPE_SECRET_KEY
    STRIPE_AVAILABLE = bool(STRIPE_SECRET_KEY)
except ImportError:
    STRIPE_AVAILABLE = False


# ============ Subscription Model ============
# Add to models.py in production

from sqlalchemy import Column, String, DateTime, Boolean
from app.models import Base


class Subscription(Base):
    """User subscription for premium access."""
    __tablename__ = "subscriptions"

    subscription_id = Column(String, primary_key=True)  # Stripe subscription ID
    user_email = Column(String, nullable=False, index=True)
    stripe_customer_id = Column(String, nullable=False)
    status = Column(String, default="active")  # active, canceled, past_due
    tier = Column(String, default="premium")  # premium, pro, etc.
    current_period_end = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    canceled_at = Column(DateTime(timezone=True), nullable=True)


# ============ Schemas ============

class CreateCheckoutRequest(BaseModel):
    """Request to create a checkout session."""
    email: EmailStr
    success_url: str
    cancel_url: str


class CheckoutSessionResponse(BaseModel):
    """Checkout session details."""
    session_id: str
    checkout_url: str


class SubscriptionStatusResponse(BaseModel):
    """Subscription status."""
    email: str
    is_premium: bool
    tier: Optional[str]
    status: Optional[str]
    expires_at: Optional[datetime]


class CustomerPortalResponse(BaseModel):
    """Customer portal session."""
    portal_url: str


# ============ Endpoints ============

@router.post("/checkout", response_model=CheckoutSessionResponse)
async def create_checkout_session(
    data: CreateCheckoutRequest,
    db: AsyncSession = Depends(get_session),
):
    """
    Create a Stripe Checkout session for premium subscription.
    Returns a URL to redirect the user to Stripe's hosted checkout.
    """
    if not STRIPE_AVAILABLE:
        raise HTTPException(
            status_code=503,
            detail="Payment processing not configured. Set STRIPE_SECRET_KEY."
        )

    try:
        # Check if customer already exists
        customers = stripe.Customer.list(email=data.email, limit=1)
        if customers.data:
            customer = customers.data[0]
        else:
            customer = stripe.Customer.create(email=data.email)

        # Create checkout session
        session = stripe.checkout.Session.create(
            customer=customer.id,
            payment_method_types=["card"],
            line_items=[{
                "price": STRIPE_PRICE_ID,
                "quantity": 1,
            }],
            mode="subscription",
            success_url=data.success_url + "?session_id={CHECKOUT_SESSION_ID}",
            cancel_url=data.cancel_url,
            metadata={
                "email": data.email,
            },
        )

        return CheckoutSessionResponse(
            session_id=session.id,
            checkout_url=session.url,
        )

    except stripe.error.StripeError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/status", response_model=SubscriptionStatusResponse)
async def get_subscription_status(
    email: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Check subscription status for an email address.
    Used to determine user's access level.
    """
    # Check database for subscription
    result = await db.execute(
        select(Subscription).where(
            Subscription.user_email == email,
            Subscription.status == "active",
        ).order_by(Subscription.created_at.desc()).limit(1)
    )
    subscription = result.scalar_one_or_none()

    if subscription:
        return SubscriptionStatusResponse(
            email=email,
            is_premium=True,
            tier=subscription.tier,
            status=subscription.status,
            expires_at=subscription.current_period_end,
        )

    return SubscriptionStatusResponse(
        email=email,
        is_premium=False,
        tier=None,
        status=None,
        expires_at=None,
    )


@router.post("/portal", response_model=CustomerPortalResponse)
async def create_customer_portal_session(
    email: str,
    return_url: str,
):
    """
    Create a Stripe Customer Portal session.
    Allows users to manage their subscription (cancel, update payment, etc.)
    """
    if not STRIPE_AVAILABLE:
        raise HTTPException(
            status_code=503,
            detail="Payment processing not configured"
        )

    try:
        # Find customer by email
        customers = stripe.Customer.list(email=email, limit=1)
        if not customers.data:
            raise HTTPException(status_code=404, detail="No subscription found")

        customer = customers.data[0]

        # Create portal session
        session = stripe.billing_portal.Session.create(
            customer=customer.id,
            return_url=return_url,
        )

        return CustomerPortalResponse(portal_url=session.url)

    except stripe.error.StripeError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/webhook")
async def handle_stripe_webhook(
    request: Request,
    stripe_signature: str = Header(..., alias="Stripe-Signature"),
    db: AsyncSession = Depends(get_session),
):
    """
    Handle Stripe webhooks for subscription lifecycle events.
    Verifies webhook signature and updates subscription status.
    """
    if not STRIPE_AVAILABLE:
        raise HTTPException(status_code=503, detail="Stripe not configured")

    try:
        payload = await request.body()
        event = stripe.Webhook.construct_event(
            payload, stripe_signature, STRIPE_WEBHOOK_SECRET
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid payload")
    except stripe.error.SignatureVerificationError:
        raise HTTPException(status_code=400, detail="Invalid signature")

    # Handle specific events
    event_type = event["type"]
    data = event["data"]["object"]

    if event_type == "checkout.session.completed":
        # New subscription created
        session = data
        if session.get("mode") == "subscription":
            subscription = stripe.Subscription.retrieve(session["subscription"])
            customer = stripe.Customer.retrieve(session["customer"])

            # Create subscription record
            sub = Subscription(
                subscription_id=subscription.id,
                user_email=customer.email,
                stripe_customer_id=customer.id,
                status="active",
                tier="premium",
                current_period_end=datetime.fromtimestamp(subscription.current_period_end),
            )
            db.add(sub)
            await db.commit()

    elif event_type == "customer.subscription.updated":
        subscription = data
        result = await db.execute(
            select(Subscription).where(
                Subscription.subscription_id == subscription["id"]
            )
        )
        sub = result.scalar_one_or_none()
        if sub:
            sub.status = subscription["status"]
            sub.current_period_end = datetime.fromtimestamp(
                subscription["current_period_end"]
            )
            await db.commit()

    elif event_type == "customer.subscription.deleted":
        subscription = data
        result = await db.execute(
            select(Subscription).where(
                Subscription.subscription_id == subscription["id"]
            )
        )
        sub = result.scalar_one_or_none()
        if sub:
            sub.status = "canceled"
            sub.canceled_at = datetime.utcnow()
            await db.commit()

    return {"status": "ok"}


@router.get("/verify-premium")
async def verify_premium_access(
    email: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Quick endpoint to verify if a user has premium access.
    Used by frontend for gating premium features.
    """
    result = await db.execute(
        select(Subscription).where(
            Subscription.user_email == email,
            Subscription.status == "active",
        ).limit(1)
    )
    subscription = result.scalar_one_or_none()

    return {
        "email": email,
        "has_premium": subscription is not None,
        "tier": subscription.tier if subscription else "free",
    }
