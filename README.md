# PixelPusher-objc

This is pretty much a direct port of Heroic Robotics' [PixelPusher-java] library.

[PixelPusher-java]: https://github.com/robot-head/PixelPusher-java

This library was built and tested for iOS.  In theory this library should work with OS X as well,
though I've never tested it there.

### Framework dependencies:

* CFNetwork.framework
* QuartzCore.framework
* Security.framework

### 3rd Party Submodules:

* [CocoaAsyncSocket]
* [HLDeferred]
* [Lumberjack]

[CocoaAsyncSocket]: https://github.com/robbiehanson/CocoaAsyncSocket
[HLDeferred]: https://github.com/heavylifters/HLDeferred-objc
[Lumberjack]: https://github.com/robbiehanson/CocoaLumberjack

### Departures from the Java implementation:

* using GCD and mostly on the main queue (thread) instead of using threads directly.  packet dispatch uses non-main queue.  i'm waiting to see when/where performance suffers to introduce non-main/concurrent queues.
* Pixel struct is float R,G,B instead of byte
* no 5-axis RGBOW pixel support (don't know what devices do this)
* PPPixelPusher defers allocation of strips so parsing status packets in PPDeviceRegistry uses less memory
* DeviceRegistry uses 3 different notifications (add, remove, update) instead of just 1 (something changed, you figure out what)

### TODO:
* instrumentation (bandwidth)
* use C-arrays instead of NSArray (measure perf diff)
* use non-main queues
* use actual pixmap for strip backing buffers
* allow strips to use external back buffer (map all strips into one single pixmap, use OS drawing routines)

