#ifndef DIFFS_H
#define DIFFS_H

#include "artrat.h"

#define COMP_TYPE0	0x00
#define COMP_TYPE1	0x01
#define COMP_TYPE2	0x02
#define COMP_TYPE3	0x03
#define COMP_TYPE4	0x04
#define COMP_TYPE5	0x05

void diffPacketProbes(artratcon *ac);

void diffPacketProbes0(artratcon *ac);
void diffPacketProbes1(artratcon *ac);
void diffPacketProbes2(artratcon *ac);
void diffPacketProbes3(artratcon *ac);
void diffPacketProbes4(artratcon *ac);
void diffPacketProbes5(artratcon *ac);

#endif
