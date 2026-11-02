// Declarations for the private macOS APIs Ledge relies on.
// MultitouchSupport, DisplayServices and SkyLight are linked from the SDK's
// PrivateFrameworks stubs; OSD and CoreBrightness are loaded at runtime so a
// missing class only disables that feature instead of breaking launch.

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOKitLib.h>
#include <stdbool.h>
#include <stdint.h>

// MARK: - MultitouchSupport

typedef void *MTDeviceRef;
typedef CFTypeRef MTActuatorRef;

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;

// One contact as delivered by MultitouchSupport (96 bytes).
typedef struct {
    int frame;
    double timestamp;
    int identifier;      // stable per finger while it stays on the surface
    int state;           // see MTTouchState
    int fingerID;
    int handID;
    MTVector normalized; // 0...1, origin at the bottom-left of the surface
    float zTotal;
    int field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;   // millimetres
    int field14;
    int field15;
    float zDensity;
} MTTouch;

typedef enum {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7,
} MTTouchState;

typedef int (*MTContactCallbackFunction)(MTDeviceRef device, const MTTouch *touches, int count, double timestamp, int frame);

CFMutableArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
void MTUnregisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
void MTDeviceStart(MTDeviceRef device, int mode);
void MTDeviceStop(MTDeviceRef device);
bool MTDeviceIsBuiltIn(MTDeviceRef device);
bool MTDeviceIsRunning(MTDeviceRef device);
OSStatus MTDeviceGetFamilyID(MTDeviceRef device, int *familyID);
OSStatus MTDeviceGetDeviceID(MTDeviceRef device, uint64_t *deviceID);
OSStatus MTDeviceGetSensorSurfaceDimensions(MTDeviceRef device, int *width, int *height); // 1/100 mm

MTActuatorRef MTActuatorCreateFromDeviceID(uint64_t deviceID);
IOReturn MTActuatorOpen(MTActuatorRef actuator);
IOReturn MTActuatorClose(MTActuatorRef actuator);
bool MTActuatorIsOpen(MTActuatorRef actuator);
IOReturn MTActuatorActuate(MTActuatorRef actuator, SInt32 actuationID, UInt32 unknown1, Float32 unknown2, Float32 unknown3);

// MARK: - DisplayServices (built-in display brightness)

int DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness);
int DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness);
bool DisplayServicesCanChangeBrightness(CGDirectDisplayID display);

// MARK: - SkyLight (lets a background app hide the cursor)

int SLSMainConnectionID(void);
CGError SLSSetConnectionProperty(int connection, int targetConnection, CFStringRef key, CFTypeRef value);

// MARK: - Runtime-loaded wrappers (LedgePrivate.m)

typedef enum {
    LGOSDImageBrightness = 1,
    LGOSDImageSpeaker = 3,
    LGOSDImageSpeakerMuted = 4,
    LGOSDImageKeyboardBacklight = 25,
    LGOSDImageKeyboardBacklightOff = 26,
} LGOSDImage;

/// Shows the system volume/brightness HUD. Returns false if OSD.framework is unavailable.
bool LGShowSystemHUD(LGOSDImage image, CGDirectDisplayID display, unsigned int filled, unsigned int total);

/// Keyboard backlight of the built-in keyboard, 0...1. Returns false when there is none.
bool LGKeyboardBacklightAvailable(void);
bool LGGetKeyboardBacklight(float *value);
bool LGSetKeyboardBacklight(float value);
