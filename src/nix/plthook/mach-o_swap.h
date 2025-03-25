#include <stdint.h>

#include <mach-o/fat.h>

extern void swap_fat_header(struct fat_header *fat_header,
                            enum NXByteOrder target_byte_order);

extern void swap_fat_arch(struct fat_arch *fat_archs, uint32_t nfat_arch,
                          enum NXByteOrder target_byte_order);
