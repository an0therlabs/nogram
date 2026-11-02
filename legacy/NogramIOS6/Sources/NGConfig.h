// Your app's credentials from https://my.telegram.org → API development tools.
// Put them in Sources/NGConfig.local.h (git-ignored) so they stay out of the
// repository:
//     #define NG_API_ID 12345
//     #define NG_API_HASH "0123456789abcdef0123456789abcdef"
#if __has_include("NGConfig.local.h")
#include "NGConfig.local.h"
#endif

#ifndef NG_API_ID
#define NG_API_ID 0
#endif
#ifndef NG_API_HASH
#define NG_API_HASH ""
#endif

// 1: Telegram's test servers (test accounts: +99966 X YYYY, the code is X five times).
#ifndef NG_TEST_SERVERS
#define NG_TEST_SERVERS 0
#endif

// MTProto layer the requests below are written against (swift_scheme.tl).
#define NG_API_LAYER 232
