.nolist

;********************************************************************************************************************************
;*																																*
;*	File: NTFS Driver.inc																										*
;*																																*
;*	This file defines constants, structures, and macros for the NTFS driver of PwnOS.											*
;*																																*
;*	Includes:																													*
;*		- <NTFS.inc>																											*
;*																																*
;*	See Also:																													*
;*		- <NTFS Driver.asm>																										*
;*		- <Files.inc>																											*
;*																																*
;*	Authors:																													*
;*		- Neil G. Dickson																										*
;*																																*
;********************************************************************************************************************************

.list
include	NTFS.inc
.nolist

OpenFileNTFS		proto	pPartition:PTR PARTITIONINFO_NTFS,pName:PTR WORD,pDirectory:PTR FILE,Access:DWORD,Creation:DWORD,Flags:DWORD
ReadFileNTFS		proto	pFile:PTR FILE_NTFS,pDestination:DWORD,nBytes:DWORD

NTFS_NUM_CACHED_CLUSTERS	equ	1

PARTITIONINFO_NTFS	STRUCT
	Header			PARTITIONINFO	<>
	LCN$MFT			QWORD	?			;These elements directly correspond with elements of NTFSBOOTSTRUCT
										;
	ClusPerFILERec	BYTE	?			;
	ClusPerINDXBuf	BYTE	?			;
	SectorsPerClus	BYTE	?			;
					BYTE	?			;padding to dword-alignment
	pMFTFileRecord	DWORD	?			;pointer to a copy of the NTFS file record of the Master File Table, which starts with an NTFSFILEHEADER
	pRootFileRecord	DWORD	?			;pointer to a copy of the NTFS file record of the root directory, which starts with an NTFSFILEHEADER
					DWORD	?			;padding to 64 bytes
PARTITIONINFO_NTFS	ENDS

FILE_NTFS		STRUCT
	Header			FILE_HARDDRIVE	<>
	FileRef			NTFSMFTREF		<>
	pFileRecord		DWORD			?	;pointer to a copy of the NTFS file record, which starts with an NTFSFILEHEADER
	pDataAttrib		DWORD			?	;pointer to within the file record in memory of the data attribute header, or index root attribute header if a directory
	VCNCache		QWORD			?	;Virtual Cluster Number of the first cached cluster
	OffsetOfCache	QWORD			?	;offset in file of the cached clusters
	pClustersCached	DWORD			?	;pointer to a cache of clusters
	nClustersCached	DWORD			?	;number of cached clusters
FILE_NTFS		ENDS

FILE_NTFS_RECORD_ALIGNMENT		equ		6

.list