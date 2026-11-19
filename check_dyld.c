#include <assert.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdio.h>

// Regression check for the launch-time SIGBUS caused by assuming image zero
// is the executable while DYLD_INSERT_LIBRARIES is active.
int main(void) {
    const struct mach_header *executable = NULL;
    uint32_t executable_index = 0;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const struct mach_header *header = _dyld_get_image_header(index);
        if (header && header->filetype == MH_EXECUTE) {
            assert(executable == NULL);
            executable = header;
            executable_index = index;
        }
    }
    Dl_info own_image;
    assert(dladdr((const void *)&main, &own_image));
    assert(executable == own_image.dli_fbase);
    printf("MH_EXECUTE selection passed. Executable image %u, image-zero type %u.\n",
           executable_index, _dyld_get_image_header(0)->filetype);
    return 0;
}
