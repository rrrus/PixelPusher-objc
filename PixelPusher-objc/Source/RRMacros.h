//
//  RRMacros.h
//  PixelPusher-objc
//
//  Created by Rus Maxham on 5/31/13.
//  Copyright (c) 2013 rrrus. All rights reserved.
//

// utility macro for making string key symbols
#define STRING_KEY(name) NSString * const name = @#name

/*!
 * strongly typed Cocoa dynamic type cast.
 * @return nil if source is not a kind of class cls, source as type cls otherwise
 * @warning This is preferable to adding it as a category on NSObject as the macro
 * can setup strong typing.
 * Source: http://stackoverflow.com/questions/1374168/is-there-an-equivalent-to-cs-dynamic-cast-in-objective-c
 * @param cls Class pointer to type-check for a given source.
 * @param source The object to be type-checked.
 */
#define DYNAMIC_CAST(cls, source)						\
({														\
	cls *inst_ = (cls *)(source);						\
	[inst_ isKindOfClass:[cls class]] ? inst_ : nil;	\
})
/*!
 * strongly typed Cocoa dynamic type cast.
 * @return nil of source is not a given protocol. a id pointer if source conforms to a given protocol.
 * @param prot, Protocol type to type-check for a given source.
 * @param source The object to be type-checked.
 */
#define DYNAMIC_CAST_PROTOCOL(prot, source)						\
({																\
	id<prot> inst_ = (id<prot>)(source);						\
	[inst_ conformsToProtocol:@protocol(prot)] ? inst_ : nil;	\
})

// lumberjack macros
//#define INIT_LOG_LEVEL_VERBOSE static const int ddLogLevel = LOG_LEVEL_VERBOSE;
//#define INIT_LOG_LEVEL_INFO static const int ddLogLevel = LOG_LEVEL_INFO;
//#define INIT_LOG_LEVEL_WARN static const int ddLogLevel = LOG_LEVEL_WARN;
//#define INIT_LOG_LEVEL_ERROR static const int ddLogLevel = LOG_LEVEL_ERROR;

// utility functions
static inline float randf(float scale)
{
	// return a float between 0 and scale
	return (float)(random() % 1000001)/1000000.0f*scale;
}

static inline float randRange(float min, float max)
{
	// return a float between min and max
	float scale = max-min;
	return min + (float)(random() % 1000001)/1000000.0f*scale;
}

static inline float randRangeMaybe(float min, float max, float likelihood, float def)
{
	if (randf(1) < likelihood)
		return def;

	// return a float between min and max
	float scale = max-min;
	return min + (float)(random() % 1000001)/1000000.0f*scale;
}
