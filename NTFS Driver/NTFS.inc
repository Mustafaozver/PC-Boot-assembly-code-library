.nolist

;********************************************************************************************************************************
;*																																*
;*	File: NTFS.inc																												*
;*																																*
;*	This file defines constants, structures, and macros for NTFS.																*
;*																																*
;*	See Also:																													*
;*		- <NTFS Driver.asm>																										*
;*		- <NTFS Driver.inc>																										*
;*																																*
;*	Authors:																													*
;*		- Neil G. Dickson																										*
;*																																*
;********************************************************************************************************************************

;********************************************************************************************************************************
;*																																*
;*	Constants: NTFS Required File Constants																						*
;*																																*
;*	These constants define file record numbers of the required NTFS metadata files.												*
;*																																*
;*	Members:																													*
;*	NTFSFILENUM_MFT				- Master File Table file																		*
;*	NTFSFILENUM_MFTMIRR			- Master File Table Mirror file																	*
;*	NTFSFILENUM_LOGFILE			- Logging File																					*
;*	NTFSFILENUM_VOLUME			- Volume information file																		*
;*	NTFSFILENUM_ATTRDEF			- Attribute information file																	*
;*	NTFSFILENUM_ROOT			- Root directory file																			*
;*	NTFSFILENUM_BITMAP			- Cluster use bitmap																			*
;*	NTFSFILENUM_BOOT			- Partition Boot Sector file																	*
;*	NTFSFILENUM_BADCLUS			- Bad Cluster list																				*
;*	NTFSFILENUM_SECURE			- Security Descriptors file																		*
;*	NTFSFILENUM_UPCASE			- Uppercase letters file																		*
;*	NTFSFILENUM_EXTEND			- Directory for extended metadata files															*
;*	NTFSFILENUM_FIRST_NORMAL	- file record number of the first non-required file or directory;								*
;*								  all normal files have a file record number greater than this									*
;*																																*
;********************************************************************************************************************************
NTFSFILENUM_MFT				equ	00h
NTFSFILENUM_MFTMIRR			equ	01h
NTFSFILENUM_LOGFILE			equ	02h
NTFSFILENUM_VOLUME			equ	03h
NTFSFILENUM_ATTRDEF			equ	04h
NTFSFILENUM_ROOT			equ	05h
NTFSFILENUM_BITMAP			equ	06h
NTFSFILENUM_BOOT			equ	07h
NTFSFILENUM_BADCLUS			equ	08h
NTFSFILENUM_SECURE			equ	09h
NTFSFILENUM_UPCASE			equ	0Ah
NTFSFILENUM_EXTEND			equ	0Bh
NTFSFILENUM_FIRST_NORMAL	equ	18h

;********************************************************************************************************************************
;*																																*
;*	Structure: NTFSBOOTSTRUCT																									*
;*																																*
;*	This structure defines the content of the boot sector (Logical Cluster Number 0) of an NTFS partition.  It is also the Data	*
;*	Attribute of the file $Boot.																								*
;*																																*
;*	Members:																													*
;*		JumpCode		- 2-byte jump and nop or 3-byte jump to after this structure											*
;*		SystemID		- "NTFS    " in ASCII (ending in 4 spaces)																*
;*		SectorSize		- size of a sector in bytes (actually defined by the device, so only here for convenience)				*
;*		SectorsPerClus	- number of sectors in a cluster																		*
;*		MediaDescriptor	- 0F8h for a hard disk																					*
;*		SectorsPerTrack	- (here for legacy compatibility)																		*
;*		nHeads			- (here for legacy compatibility)																		*
;*		Unused			- probably unused; almost always 80008000h (some obscure report of 80000000h on a USB key)				*
;*		nSectors		- number of sectors in the partition																	*
;*		LCN$MFT			- Logical Cluster Number of the first cluster (Virtual Cluster Number 0) of $MFT, the Master File Table	*
;*		LCN$MFTMirr		- LCN of VCN 0 of $MFTMirr, the Mirror of the first 4 FILE records of $MFT (possibly always 8KB size)	*
;*		ClusPerFILERec	- # of clusters / FILE record; signed byte value: if negative, size in bytes of FILE record = 2^(-value)*
;*		ClusPerINDXBuf	- # of clusters / Index Buffer; signed byte value: if negative byte value,								*
;*						  size in bytes of INDX buffer = 2^(-value)																*
;*		VolumeSerialNum	- serial number of the volume																			*
;*																																*
;********************************************************************************************************************************
NTFSBOOTSTRUCT	STRUCT
	JumpCode		byte	3 dup (?)
	SystemID		byte	8 dup (?)
	SectorSize		word	?
	SectorsPerClus	byte	?
					byte	7 dup (?)
	MediaDescriptor	byte	?
					byte	2 dup (?)
	SectorsPerTrack	word	?
	nHeads			word	?
					byte	8 dup (?)	;unused: zero
	Unused			dword	?
	nSectors		qword	?
	LCN$MFT			qword	?
	LCN$MFTMirr		qword	?
	ClusPerFILERec	dword	?
	ClusPerINDXBuf	dword	?
	VolumeSerialNum	qword	?
NTFSBOOTSTRUCT	ENDS

;********************************************************************************************************************************
;*																																*
;*	Structure: NTFSMFTREF																										*
;*																																*
;*	This structure defines a file reference into the Master File Table of an NTFS partition.									*
;*																																*
;*	Members:																													*
;*		FILERecNum		- index of the file record in the Master File Table														*
;*		SeqNum			- sequence number of the file (to determine whether this reference is to a deleted file)				*
;*																																*
;********************************************************************************************************************************
NTFSMFTREF		STRUCT
	FILERecNum		fword	?
	SeqNum			word	?
NTFSMFTREF		ENDS

;********************************************************************************************************************************
;*																																*
;*	Structure: NTFSFILEHEADER																									*
;*																																*
;*	This structure defines NTFS's "FILE record" header. FILE records are in the MFT (Master File Table).						*
;*																																*
;*	Update Sequence Number word follows, then Update Sequence Array of words, then follows the attributes,						*
;*	followed by a dword of 0FFFFFFFFh (<NTFSATTRIBTYPE_END_MARKER>)																*
;*																																*
;*	Members:																													*
;*		Signature		- "FILE" in ASCII																						*
;*		OffUpdateSeq	- offset in structure of update sequence number															*
;*		LenUpdateSeq	- Size in words of update sequence number & array (i.e. 1 + length of array)							*
;*		LogSeqNum		- $LogFile Sequence Number (LSN): changed every time this record is modified							*
;*		SeqNum			- # of times this record has been reused, incremented (skipping 0) when and only when the file is		*
;*						  deleted; it is left as 0 if set to 0																	*
;*		HardLinkCount	- 																										*
;*		OffAttributes	- offset in structure of first attribute																*
;*		Flags			- 																										*
;*		RealSize		- # of bytes used in the allocated FILE record, padded to 8 byte boundary								*
;*		AllocSize		- # of bytes allocated for the FILE record	;should be = to size of FILE record as defined in $Boot,	*
;*						  except when cluster size is < 1KB ???																	*
;*		BaseFILERef		- MFT reference to the Base FILE record, or 0 if this is the Base FILE Record of the file				*
;*		NextAttributeID	- 0 before any attributes added (whenever this record is "reused" after deletion or initially),			*
;*						  incremented when adding each attribute																*
;*		FILERecNum		- Windows XP only: index of this FILE record in the MFT													*
;*																																*
;********************************************************************************************************************************
NTFSFILEHEADER	STRUCT
	Signature		dword	?
	OffUpdateSeq	word	?
	LenUpdateSeq	word	?
	LogSeqNum		qword	?
	SeqNum			word	?
	HardLinkCount	word	?
	OffAttributes	word	?
	Flags			word	?
	RealSize		dword	?
	AllocSize		dword	?
	BaseFILERef		NTFSMFTREF	<>
	NextAttributeID	word	?
					word	?			;Windows XP only: aligns to 4-byte boundary
	FILERecNum		dword	?
NTFSFILEHEADER	ENDS

;********************************************************************************************************************************
;*																																*
;*	Constants: NTFS File Flag Constants																							*
;*																																*
;*	These constants define flags for the <NTFSFILEHEADER> structure.															*
;*																																*
;*	Members:																													*
;*	NTFSFILEFLAG_USED			- set if the FILE record is being used (i.e. represents a file)									*
;*	NTFSFILEFLAG_DIRECTORY		- set if the FILE record is for a directory														*
;*																																*
;********************************************************************************************************************************
NTFSFILEFLAG_USED			equ	1
NTFSFILEFLAG_DIRECTORY		equ	2

;********************************************************************************************************************************
;*																																*
;*	Section: NTFS File Attribute Structures																						*
;*																																*
;*	These structures are for attributes following the <NTFSFILEHEADER> structure.												*
;*																																*
;********************************************************************************************************************************

NTFSATTRIBHEADER	STRUCT
	AttributeType	dword	?
	ThisLength		dword	?			;includes length of this header, rest of header, and any resident part of attribute
	NonResident?	byte	?			;FALSE if resident (in MFT), and TRUE if non-resident (in clusters outside MFT)
	NameLength		byte	?			;# of characters (words) in name, or 0 if not named
	NameOffset		word	?			;offset in structure to name	;0 if no name, 18h if named-resident, 40h if named-non-resident
	Flags			word	?			;0 if resident
	AttributeID		word	?			;each attribute has a unique ID
NTFSATTRIBHEADER	ENDS

NTFSATTRIBHEADER_RES	STRUCT			;header for resident attributes
	AttributeType	dword	?
	ThisLength		dword	?			;includes length of this header, rest of header, and any resident part of attribute
	NonResident?	byte	?			;FALSE if resident (in MFT), and TRUE if non-resident (in clusters outside MFT)
	NameLength		byte	?			;# of characters (words) in name, or 0 if not named
	NameOffset		word	?			;offset in structure to name	;0 if no name, 18h if named-resident, 40h if named-non-resident
	Flags			word	?			;0 if resident
	AttributeID		word	?			;each attribute has a unique ID
	AttributeLength	dword	?			;# of bytes in Attribute, which follows name if named, which follows this header
	AttributeOffset	word	?			;18h if no name, after name if named
	Indexed?		byte	?
					byte	?			;1 byte to pad header size to 18h
										;if named, unicode name without null terminator then attribute follow immediately, else attribute follows immediately
										;attribute is rounded up to a multiple of 4 bytes	;assuming this doesn't affect AttributeLength???
NTFSATTRIBHEADER_RES	ENDS

NTFSATTRIBHEADER_NRES	STRUCT
	AttributeType	dword	?
	ThisLength		dword	?			;includes length of this header, rest of header, and any resident part of attribute
	NonResident?	byte	?			;FALSE if resident (in MFT), and TRUE if non-resident (in clusters outside MFT)
	NameLength		byte	?			;# of characters (words) in name, or 0 if not named
	NameOffset		word	?			;offset in structure to name	;0 if no name, 18h if named-resident, 40h if named-non-resident
	Flags			word	?			;0 if resident
	AttributeID		word	?			;each attribute has a unique ID
	FirstVCN		qword	?			;first Virtual Cluster Number within attribute data
	LastVCN			qword	?			;last VCN within attribute data
	DataRunsOffset	word	?			;40h if not named, after name if named
	CompressionUnit	word	?			;0 if not compressed, else a power of 2 indicating the nubmer of clusters in 1 compression unit (or does this value hold the exponent???)
										;apparently usually 16 clusters, or 2^4
					dword	?			;padding to 8-byte boundary
	AllocSize		qword	?			;# of bytes allocated for attribute (rounded up to size of cluster)
	RealSize		qword	?			;# of bytes used in allocated attribute
	InitDataSize	qword	?			;check to see when is this not equal to AllocSize!!! probably different by amount empty in last cluster??? possibly with compression too???
										;if named, unicode name without null terminator then data runs follow immediately, else data runs follows immediately
										;data runs rounded up to a multiple of 4 bytes	;how does this work???
NTFSATTRIBHEADER_NRES	ENDS

NTFSATTRIBFLAG_COMPRESSED	equ	0001h	;only for non-resident data attribute
NTFSATTRIBFLAG_ENCRYPTED	equ	4000h
NTFSATTRIBFLAG_SPARSE		equ	8000h	;only for non-resident data attribute	;sparse indicates ???completely??? filled with 0's, so needs no disk space
										;this may just indicate that at least one data run is sparse (0-byte offset)
										;sparse data runs also used to pad blocks of a compressed file to the compression unit size

NTFSATTRIBTYPE_STDINFO		equ	10h		;$STANDARD_INFORMATION
NTFSATTRIBTYPE_ATTRIBLIST	equ	20h		;$ATTRIBUTE_LIST
NTFSATTRIBTYPE_FILENAME		equ	30h		;$FILE_NAME
NTFSATTRIBTYPE_OBJECTID		equ	40h		;
NTFSATTRIBTYPE_SECURITYDESC	equ	50h
NTFSATTRIBTYPE_VOLUMENAME	equ	60h
NTFSATTRIBTYPE_VOLUMEINFO	equ	70h
NTFSATTRIBTYPE_DATA			equ	80h
NTFSATTRIBTYPE_INDEXROOT	equ	90h		;$INDEX_ROOT
NTFSATTRIBTYPE_INDEXALLOC	equ	0A0h	;$INDEX_ALLOCATION
NTFSATTRIBTYPE_BITMAP		equ	0B0h
NTFSATTRIBTYPE_REPARSEPOINT	equ	0C0h
NTFSATTRIBTYPE_EXTATTRINFO	equ	0D0h
NTFSATTRIBTYPE_EXTATTR		equ	0E0h
NTFSATTRIBTYPE_UTILSTREAM	equ	100h
NTFSATTRIBTYPE_END_MARKER	equ	0FFFFFFFFh

NTFSSTDINFOATTRIB	STRUCT				;$STANDARD_INFORMATION Attribute (resident)
	CreationTime	qword	?
	AlteredTime		qword	?
	MFTChangedTime	qword	?
	ReadTime		qword	?
	FilePermissions	dword	?
	MaxNumVersions	dword	?			;0 means versions not used
	Version			dword	?			;0 if MaxNumVersions is 0					;possibly never used
	ClassID			dword	?			;Class Id from bidirectional Class Id index	;possibly never used
	OwnerID			dword	?			;ID of user owning the file, used in $Quota	;if 0, quotas disabled
	SecurityID		dword	?			;not a "Security Identifier"	;used in $Secure
	QuotaCharged	qword	?			;# of bytes charged from user's quota		;if 0, quotas disabled
	UpdateSeqNum	qword	?			;index into $UsnJrnl						;if 0, the USN Journal is disabled
NTFSSTDINFOATTRIB	ENDS

NTFSSTDINFOFLAG_READONLY		equ	0001h
NTFSSTDINFOFLAG_HIDDEN			equ	0002h
NTFSSTDINFOFLAG_SYSTEM			equ	0004h
NTFSSTDINFOFLAG_ARCHIVE			equ	0020h
NTFSSTDINFOFLAG_DEVICE			equ	0040h
NTFSSTDINFOFLAG_NORMAL			equ	0080h
NTFSSTDINFOFLAG_TEMPORARY		equ	0100h
NTFSSTDINFOFLAG_SPARSE			equ	0200h
NTFSSTDINFOFLAG_REPARSEPOINT	equ	0400h
NTFSSTDINFOFLAG_COMPRESSED		equ	0800h
NTFSSTDINFOFLAG_OFFLINE			equ	1000h
NTFSSTDINFOFLAG_NOTINDEXED		equ	2000h		;Not Content Indexed
NTFSSTDINFOFLAG_ENCRYPTED		equ	4000h

NTFSFILENAMEATTRIB	STRUCT				;$FILE_NAME Attribute (resident)	;all fields, except parent directory, only updated when filename changed
										;files have more than 1 $FILE_NAME attribute when they have more than 1 hard link
	ParentDirRef	NTFSMFTREF	<>		;MFT reference to the Base FILE record of parent directory
	CreationTime	qword	?
	AlteredTime		qword	?
	MFTChangedTime	qword	?
	ReadTime		qword	?
	AllocFileSize	qword	?
	RealFileSize	qword	?
	Flags			dword	?			;related to NTFSSTDINFOATTRIB.FilePermissions
	EABufSizeOrReparseType	dword	?
	FilenameLength	byte	?			;length in unicode characters (words)
	Namespace		byte	?
										;unicode filename without null terminator follows
NTFSFILENAMEATTRIB	ENDS

NTFSFILENAMEFLAG_READONLY		equ	NTFSSTDINFOFLAG_READONLY
NTFSFILENAMEFLAG_HIDDEN			equ	NTFSSTDINFOFLAG_HIDDEN
NTFSFILENAMEFLAG_SYSTEM			equ	NTFSSTDINFOFLAG_SYSTEM
NTFSFILENAMEFLAG_ARCHIVE		equ	NTFSSTDINFOFLAG_ARCHIVE
NTFSFILENAMEFLAG_DEVICE			equ	NTFSSTDINFOFLAG_DEVICE
NTFSFILENAMEFLAG_NORMAL			equ	NTFSSTDINFOFLAG_NORMAL
NTFSFILENAMEFLAG_TEMPORARY		equ	NTFSSTDINFOFLAG_TEMPORARY
NTFSFILENAMEFLAG_SPARSE			equ	NTFSSTDINFOFLAG_SPARSE
NTFSFILENAMEFLAG_REPARSEPOINT	equ	NTFSSTDINFOFLAG_REPARSEPOINT
NTFSFILENAMEFLAG_COMPRESSED		equ	NTFSSTDINFOFLAG_COMPRESSED
NTFSFILENAMEFLAG_OFFLINE		equ	NTFSSTDINFOFLAG_OFFLINE
NTFSFILENAMEFLAG_NOTINDEXED		equ	NTFSSTDINFOFLAG_NOTINDEXED		;Not Content Indexed
NTFSFILENAMEFLAG_ENCRYPTED		equ	NTFSSTDINFOFLAG_ENCRYPTED
NTFSFILENAMEFLAG_DIRECTORY		equ	10000000h	;copy of bit from FILE record header
NTFSFILENAMEFLAG_INDEXVIEW		equ	20000000h	;copy of bit from FILE record header??? what bit??? the one from NTFSATTRIBHEADER_RES???

NTFS_NAMESPACE_POSIX			equ	0
NTFS_NAMESPACE_WIN32			equ	1
NTFS_NAMESPACE_DOS				equ	2
NTFS_NAMESPACE_WIN32_AND_DOS	equ	3

;********************************************************************************************************************************
;*																																*
;*	Section: NTFS Directory File Structures																						*
;*																																*
;*	These structures are for attributes of directories following the <NTFSFILEHEADER> structure.								*
;*																																*
;********************************************************************************************************************************
NTFSINDEXROOTATTRIB	STRUCT						;$INDEX_ROOT Attribute (resident)
	IndexingAttributeType	dword	?			;NTFSATTRIBTYPE_FILENAME for directories (sort the tree by filenames)
												;0 for "view indexes" (whatever those are)
	CollationRule			dword	?			;number indicating rule used for sorting by the attribute indicated in IndexingAttributeType
												;always the same for NTFSATTRIBTYPE_FILENAME, but what value is it??? spec says "COLLATION_FILENAME", output indicates value is 1
	BytesPerIndexNode		dword	?			;size of index node (block of entries) in $INDEX_ALLOCATION
	ClustersPerIndexNode	byte	?			;# of clusters per index node (block of entries) in $INDEX_ALLOCATION, or log of BytesPerIndexNode if <1 cluster
												;must be power of 2 size represented
							byte	3 dup (?)	;padding to 8-byte boundary
NTFSINDEXROOTATTRIB	ENDS

NTFSINDEXHEADER		STRUCT						;in $INDEX_ROOT Attribute
	OffFirstIndexEntry		dword	?
	TotalSizeIndexEntries	dword	?
	AllocSizeIndexEntries	dword	?
	Flags					byte	?
							byte	3 dup (?)
NTFSINDEXHEADER		ENDS

NTFSINDEXFLAG_LARGE				equ	1			;iff set, $INDEX_ALLOCATION and $BITMAP attributes exist for this index

NTFSINDEXENTRY		STRUCT
	FILERef					NTFSMFTREF	<>
	ThisLength				word	?
	KeyLength				word	?
	Flags					byte	?
							byte	3 dup (?)	;padding to 8-byte boundary
												;Key immediately follows.  The Key is a copy of the attribute being sorted on, usually $FILE_NAME, excluding the attribute header.
												;VCN of a subnode in $INDEX_ALLOCATION occurs in the last 8 bytes of the entry (at ThisLength-8)
NTFSINDEXENTRY		ENDS

NTFSINDEXENTRYFLAG_SUBNODE		equ	1			;set if entry has a subnode
NTFSINDEXENTRYFLAG_LAST			equ	2			;set if last entry in current list of entries (file reference not valid if last, only provides subnode if necessary)

;$INDEX_ALLOCATION Attribute (non-resident) has only NTFSATTRIBHEADER_NRES followed by Data Runs
;The clusters contain a NTFSINDEXALLOCHEADER followed by a variable number of NTFSINDEXENTRYs
NTFSINDEXALLOCHEADER		STRUCT				;in $INDEX_ALLOCATION Attribute
	Signature				dword	?			;"INDX"
	OffUpdateSeq			word	?			;offset in structure of update sequence number
	LenUpdateSeq			word	?			;Size in words of update sequence number & array (i.e. 1 + length of array)
	LogSeqNum				qword	?			;$LogFile Sequence Number (LSN): changed every time this record is modified
	ThisVCN					qword	?			;Virtual Cluster Number of this index node within the $INDEX_ALLOCATION
	OffFirstIndexEntry		dword	?			;Offset RELATIVE TO THIS OFFSET (18h) of first entry in node
	TotalSizeIndexEntries	dword	?
	AllocSizeIndexEntries	dword	?
	Flags					byte	?
							byte	3 dup (?)
												;Update Sequence Number word follows, then Update Sequence Array of words
NTFSINDEXALLOCHEADER		ENDS

NTFSINDEXALLOCFLAG_HASCHILDREN	equ	1

.list