# CAN Bus DBC Files

This directory contains DBC (Database CAN) files for decoding proprietary ECU CAN messages.

## Included Files

- `motec_generic.dbc` - Generic MoTeC template with common message IDs (256-264)

## MoTeC ECU Setup

MoTeC ECUs (M1, M150, M130, M84, M800 series) have configurable CAN output. For best results, export your specific configuration:

### Exporting from MoTeC i2 Pro

1. Connect to your ECU and download the current configuration
2. Open MoTeC i2 Pro
3. Go to **File -> Export -> CAN Protocol (DBC)**
4. Save the file to this directory (e.g., `my_m150.dbc`)
5. Run: `python can_telemetry.py --dbc dbc/my_m150.dbc`

### Using the Generic Template

If you don't have i2 Pro or want to test quickly:

```bash
python can_telemetry.py --motec --interface can0
```

This uses the generic template which expects these CAN IDs:
- 0x100 (256): Engine RPM, Throttle, Load, Gear
- 0x101 (257): Coolant Temp, IAT, Oil Pressure, Fuel Pressure
- 0x102 (258): MAP, Lambda, Fuel Used, Battery
- 0x103 (259): Ground Speed, Wheel Speeds FL/FR
- 0x104 (260): Wheel Speeds RL/RR, Lat/Long Accel
- 0x105 (261): Suspension Positions
- 0x106 (262): Steering, Brake Pressures
- 0x107 (263): GPS Lat/Lon
- 0x108 (264): GPS Speed/Heading/Alt

### Configuring MoTeC CAN Output

In MoTeC ECU Manager:

1. Go to **CAN -> CAN Bus Configuration**
2. Set baud rate to **1 Mbit/s** (recommended) or 500 kbit/s
3. Add transmit messages matching the IDs above
4. Map your logged channels to the appropriate signals

## Other ECUs

### AEM Infinity / Series 2

AEM provides DBC files on their website:
https://www.aemelectronics.com/support

### Haltech Elite / Nexus

Haltech DBC files can be exported from NSP software:
1. Open your tune in NSP
2. Go to **CAN -> CAN Bus Setup**
3. Click **Export DBC**

### Link G4+ / G4X

Link provides DBC files in their software downloads:
https://www.linkecu.com/software/

## Creating Custom DBC Files

If your ECU doesn't have a DBC file available, you can create one manually:

1. Document your CAN message IDs and signal layouts
2. Use a tool like **Vector CANdb++** or **Kvaser Database Editor**
3. Define each message with its signals, scaling, and units
4. Save as `.dbc` format

### Signal Naming Convention

For automatic mapping, use these signal names (or variations):

| Signal Name | Mapped To |
|------------|-----------|
| Engine_RPM, RPM | rpm |
| Ground_Speed, Vehicle_Speed | speed_kph |
| Throttle_Position, TPS | throttle_pct |
| Engine_Coolant_Temp, ECT | coolant_temp |
| Oil_Pressure | oil_pressure |
| Fuel_Pressure | fuel_pressure |
| Gear, Gear_Position | gear |
| Susp_Pos_FL, Damper_Pos_FL | suspension_fl |

See `can_telemetry.py` for the full list of supported signal name variations.
