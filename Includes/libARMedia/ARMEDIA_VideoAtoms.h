/*
 * ARMEDIA_VideoAtoms.h
 *
 * Created by n.brulez on 19/08/11
 * Copyright 2011 Parrot SA. All rights reserved.
 *
 */
#ifndef _ARMEDIA_VIDEOATOMS_H_
#define _ARMEDIA_VIDEOATOMS_H_

#include <inttypes.h>
#include <stdio.h>
#include <time.h>
#include <libARMedia/ARMEDIA_VideoEncapsuler.h>

#define ARMEDIA_VIDEOATOMS_PVAT "pvat"

#define ARMEDIA_ATOM_TAG_SIZE 4

typedef struct
{
  uint64_t size;
  char tag[ARMEDIA_ATOM_TAG_SIZE];
  uint8_t *data;
  uint8_t wide;
} movie_atom_t;

typedef struct
{
    uint64_t size;
    int flag;
    long long offset;
} atom_check_return;

#define atom_ntohll(x)  swap_uint64(x)

/* Atoms :
LEGEND :
-> specific = specific function to generate this atom
-> empty = use atomFromData (0, "name", NULL);
-> from data = use atomFromData (dataSize, "name", dataPointer);

ftyp -> specific
mdat -> specific (include freeAtom if needed)
moov -> empty
 |- mvhd -> specific
 |- trak -> empty
 |   |- tkhd -> specific
 |   \- mdia -> empty
 |       |- mdhd -> specific
 |       |- hdlr -> specific (for mdia)
 |       \- minf -> empty
 |           |- vmhd -> specific
 |           |- hdlr -> specific (for minf)
 |           |- dinf -> empty
 |           |   \- dref -> specific
 |           \- stbl -> empty
 |               |- stsd -> specific
 |               |- stts -> from data
 |               |- stss -> from data (i frame positions as uint32_t network endian)
 |               |- stsc -> specific
 |               |- stsz -> from data (frames sizes as uint32_t network endian)
 |               \- stco -> from data (frames offset as uint32_t network endian)
 \- udta -> empty
     |- meta1 -> all meta specific (metadataAtomFromTagAndValue)
   [...]
     \- metaN -> all meta specific (metadataAtomFromTagAndValue)
pvat -> specific
*/

/* REMINDER : NEVER INCLUDE A MDAT ATOM INTO ANY OTHER ATOM */

/* GENERIC */
movie_atom_t *atomFromData (uint32_t data_size, const char *tag, const uint8_t *data);
void insertAtomIntoAtom (movie_atom_t *container, movie_atom_t **leaf); // will free leaf
int writeAtomToFile (movie_atom_t **atom, FILE *file); // Will free _atom
void freeAtom (movie_atom_t **atom);

/* SPECIFIC */
movie_atom_t *ftypAtomForFormatAndCodecWithOffset (eARMEDIA_ENCAPSULER_CODEC codec, uint32_t *offset);
movie_atom_t *mdatAtomForFormatWithVideoSize (uint64_t videoSize);
movie_atom_t *mvhdAtomFromFpsNumFramesAndDate (uint32_t timescale, uint32_t duration, time_t date);
movie_atom_t *tkhdAtomWithResolutionNumFramesFpsAndDate (uint32_t w, uint32_t h, uint32_t timescale, uint32_t duration, time_t date);
movie_atom_t *mdhdAtomFromFpsNumFramesAndDate (uint32_t timescale, uint32_t duration, time_t date);
movie_atom_t *hdlrAtomForMdia ();
movie_atom_t *vmhdAtomGen ();
movie_atom_t *hdlrAtomForMinf ();
movie_atom_t *drefAtomGen ();
movie_atom_t *stsdAtomWithResolutionAndCodec (uint32_t w, uint32_t h, eARMEDIA_ENCAPSULER_CODEC codec);
movie_atom_t *stsdAtomWithResolutionCodecSpsAndPps (uint32_t w, uint32_t h, eARMEDIA_ENCAPSULER_CODEC codec, uint8_t *sps, uint32_t spsSize, uint8_t *pps, uint32_t ppsSize);
movie_atom_t *stscAtomGen ();
movie_atom_t *metadataAtomFromTagAndValue (const char *tag, const char *value);
movie_atom_t *pvatAtomGen(const char *jsonString);

/**
 * @brief Read atom data from a video file into a self alloced array
 * Thid function get the atom data from a video file and convert it to the latest version
 * This function alloc (using vp_os_calloc) the return pointer. Application MUST handle the free of the pointer.
 * @param videoFile Pointer to the video file.
 * @param atom The name of the atom to extract. If an inner atom is required, use / to separate levels.
 * @param dataSize Pointer which will hold the size of the returned data.
 * @return A new, malloc'd, pointer of pvat data filled with data buffer. In case of failure, returns NULL.
 * @note The video FILE* pointer position will be modified by this call.
 */
uint8_t *createDataFromFile (FILE *videoFile, const char *atom, uint32_t *dataSize);

/**
 * @brief Read atom data from atom into a self alloced array
 * This function get the atom data from a video and convert it to the latest version
 * This function alloc (using vp_os_calloc) the return pointer. Application MUST handle the free of the pointer.
 * @param atomBuffer Pointer to the atom data (not including the leading size and atom tag)
 * @param atomSize Size of the atom. This is used to avoid overflow, or if the atom size was set to zero
 * @return A new, malloc'd, pointer of atom data filled with data. In case of failure, returns NULL
 */
uint8_t *createDataFromAtom (uint8_t *atomBuffer, const int atomSize);

/**
 * @brief Read FPS from a given video file
 * This function get the FPS of a given video file
 * @param videoFile Pointer to the video file
 * @return The number of frames per second of the video. Returns zero if we were unable to read the actual value.
 * @note The video FILE* pointer position will be modified by this call
 * @note This call may fail on non-AR.Drone generated videos
 */
uint32_t getVideoFpsFromFile (FILE *videoFile);

/**
 * @brief Read FPS from a given video mdhd atom
 * This function get the FPS of a given video mdhd atom
 * @param mdhdAtom Pointer to the video atom
 * @param atomSize Size of the video atom pointer
 * @return The number of frames per second of the video. Returns zero if we were unable to read the actual value.
 * @note This call may fail on non-AR.Drone generated videos
 */
uint32_t getVideoFpsFromAtom (uint8_t *mdhdAtom, const int atomSize);

/**
 * @brief Read size and atomName from a given buffer of atom
 * This function get the size and the name of a given buffer atom
 * @param buffer Pointer to the buffer atom
 * @param offset Pointer of number of bytes offset in the video
 * @param tag char Pointer of the wanted atom Name
 * @return int return 0 if the tag is not found and increment the off with the atom size else return 1 if success
 */
int seekMediaBufferToAtom (uint8_t *buff, long long *offset, const char *tag);

/**
 * @brief This function reversed the byte order of a uint64_t
 * @param value in uint64_t
 * @return uint64_t reversed
*/
uint64_t swap_uint64(uint64_t value);

char* ARMEDIA_VideoAtom_GetPVATString(eARDISCOVERY_PRODUCT id, char* uuid, char* runDate, struct tm* mediaDate);

#endif // _ARMEDIA_VIDEO_ATOMS_H_
