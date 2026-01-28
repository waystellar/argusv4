"""
Leaderboard and splits API routes.
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.models import Event
from app.schemas import LeaderboardResponse, SplitsResponse
from app.services.checkpoint_service import calculate_leaderboard, calculate_splits

router = APIRouter(prefix="/api/v1/events", tags=["leaderboard"])


@router.get("/{event_id}/leaderboard", response_model=LeaderboardResponse)
async def get_leaderboard(
    event_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get current race standings.
    Ranked by checkpoint progression, then by crossing time.
    """
    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Event not found")

    return await calculate_leaderboard(db, event_id)


@router.get("/{event_id}/splits", response_model=SplitsResponse)
async def get_splits(
    event_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get split times at each checkpoint.
    Shows time deltas from leader at each checkpoint.
    """
    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Event not found")

    return await calculate_splits(db, event_id)
