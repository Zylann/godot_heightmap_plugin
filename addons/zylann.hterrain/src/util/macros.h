#ifndef MACROS_H
#define MACROS_H

#include <assert.h>

#define TOOLS_ENABLED

#define memnew(m_class) new m_class
#define memdelete(m_obj) delete m_obj

// I use this to recognize debug code
#define DDD(...) printf(__VA_ARGS__); printf("\n")

#endif // MACROS_H
