//
//  PPPrivate.h
//  PixelPusher-objc
//
//	Private definitions for use in compiling every file in the PP library.
//	Use it outside the library too if you find it useful!  :-)
//
//  Created by Christopher Schardt in January of 2015
//

#import <Foundation/Foundation.h>


/////////////////////////////////////////////////
#pragma mark - TYPES:


/////////////////////////////////////////////////
#pragma mark - ASSERTION MACROS:

#ifndef ASSERT

#if DO_ASSERT

#define ALL_ASSERTS_ARE_HARD	FALSE	// set to true if ASSERT/VERIFY() getting called in worker thread

#if ALL_ASSERTS_ARE_HARD
	#define ASSERT(expression, ...)			assert(expression)
	#define VERIFY(expression, ...)			assert(expression)
#else
	// Use raise(SIGTRAP) rather than assert() since this will allow execution
	// to continue in the debugger after the assertion.
	#define ASSERT(expression, ...)			if (!(expression)) raise(SIGTRAP)
	#define VERIFY(expression, ...)			if (!(expression)) raise(SIGTRAP)
#endif

// These versions should be used in any code that might be executed in
// a worker thread.
#define ASSERT_IN_THREAD(expression, ...)	assert(expression)
#define VERIFY_IN_THREAD(expression, ...)	assert(expression)

#else

#define	ASSERT(expression, ...)
#define VERIFY(expression, ...)				(expression)
#define	ASSERT_IN_THREAD(expression, ...)
#define VERIFY_IN_THREAD(expression, ...)	(expression)

#endif

#endif


/////////////////////////////////////////////////
#pragma mark - LOGGING MACROS:

#ifndef LOG

#ifdef DO_LOG
	#define LOG(string, ...)		NSLog((string), ##__VA_ARGS__)
#else
	#define LOG(string, ...)
#endif

#endif

