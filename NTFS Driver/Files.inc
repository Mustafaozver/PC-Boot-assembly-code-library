.nolist

;********************************************************************************************************************************
;*																																*
;*	File: Files.inc																												*
;*																																*
;*	This file defines constants, structures, and macros for file management functions of PwnOS.									*
;*																																*
;*	Includes:																													*
;*		- <NTFS Driver.inc>																										*
;*																																*
;*	See Also:																													*
;*		- <Files.asm>																											*
;*																																*
;*	Authors:																													*
;*		- Neil G. Dickson																										*
;*																																*
;********************************************************************************************************************************

OpenFile			proto	pName:PTR WORD,Access:DWORD,Creation:DWORD,Flags:DWORD
GetFileSize			proto	pFile:PTR FILE
ReadFile			proto	pFile:PTR FILE,pDestination:DWORD,nBytes:DWORD
WriteFile			proto	pFile:PTR FILE,pSource:DWORD,nBytes:DWORD
CloseFile			proto	pFile:PTR FILE
GetCurrentDirectory	proto

OPENFILE_FLAG_SYSTEM		equ	1	;indicates that the file structure and data should be placed on the system heap

;********************************************************************************************************************************
;*																																*
;*	Structure: ATADEVICEINFO																									*
;*																																*
;*	This structure defines a hardware device connected through the ATA controller (mostly harddrives and CD/DVD drives).		*
;*																																*
;*	Members:																													*
;*		PartitionType	- always PARTITIONTYPE_DRIVE so that it is possible to figure out whether the parent of a partition		*
;*						  is another partition or a drive																		*
;*		DeviceNum		- the I/O device number, one of the ATA constants of <I/O Device Numbers>								*
;*		nSectors		- the number of sectors on the drive																	*
;*		Flags			- miscellaneous flags, from <ATA Driver Flags>															*
;*		AccessLock		- <LOCKSTRUCT> to gain exclusive access to the device													*
;*		SupportFlags	- flags indicating feature support from the ATA Identify Device command's structure						*
;*		pPartitions		- array of 4 pointers to <PARTITIONINFO> structures (or NULL where there is no partition)				*
;*																																*
;********************************************************************************************************************************
ATADEVICEINFO		STRUCT
	PartitionType	dword	?
	DeviceNum		dword	?
	nSectors		qword	?
	Flags			qword	?
					qword	?	;padding so that sizeof ATADEVICEINFO is a multiple of 16 bytes
	AccessLock		LOCKSTRUCT	<>
	SupportFlags	dword	4 dup (?)
	pPartitions		dword	4 dup (?)
ATADEVICEINFO		ENDS

;********************************************************************************************************************************
;*																																*
;*	Structure: PARTITIONINFO																									*
;*																																*
;*	This structure defines a partition on a drive.  Specific partition types each have their own structures with this as		*
;*	a header, e.g. <PARTITIONINFO_EXTENDED> and <PARTITIONINFO_NTFS>.															*
;*																																*
;*	Members:																													*
;*		PartitionType	- one of the <Partition Type Constants>, except not PARTITIONTYPE_DRIVE									*
;*		DeviceNum		- the I/O device number of the device containing the partition, one of the <I/O Device Numbers>			*
;*		pParent			- address of the parent <PARTITIONINFO> structure or parent device structure							*
;*		Flags			- miscellaneous flags, e.g. PARTITIONINFO_FLAG_BOOTABLE													*
;*		FirstSector		- LBA number of the first sector of the partition														*
;*		nSectors		- number of sectors in the partition																	*
;*		Synonym			- unicode string of up to 4 characters indicating a synonym for this partition, or all 0 if none		*
;*																																*
;********************************************************************************************************************************
PARTITIONINFO		STRUCT
	PartitionType	dword	?
	DeviceNum		dword	?
	pParent			dword	?
	Flags			dword	?
	FirstSector		qword	?
	nSectors		qword	?
	Synonym			dw		4 dup (?)
PARTITIONINFO		ENDS

PARTITIONINFO_ALIGNMENT		equ	4	;PARTITIONINFO aligned to 16 bytes

PARTITIONINFO_FLAG_BOOTABLE	equ	1	;partition is marked bootable if set

;********************************************************************************************************************************
;*																																*
;*	Structure: PARTITIONINFO_EXTENDED																							*
;*																																*
;*	This structure defines an extended partition on a drive.																	*
;*																																*
;*	Members:																													*
;*		Header			- the <PARTITIONINFO> structure component of this structure												*
;*		pPartitions		- array of 4 pointers to <PARTITIONINFO> structures (or NULL where there is no partition)				*
;*																																*
;********************************************************************************************************************************
PARTITIONINFO_EXTENDED	STRUCT
	Header			PARTITIONINFO	<>
	pPartitions		dword	4 dup (?)
PARTITIONINFO_EXTENDED	ENDS

;********************************************************************************************************************************
;*																																*
;*	Constants: Partition Type Constants																							*
;*																																*
;*	These constants identify partition types.																					*
;*																																*
;*	Members:																													*
;*	PARTITIONTYPE_DRIVE			- indicates that the structure doesn't represent a partition, but rather a drive,				*
;*								  e.g. <ATADEVICEINFO>																			*
;*	PARTITIONTYPE_EXTENDED		- indicates that the structure is a <PARTITIONINFO_EXTENDED> structure							*
;*	PARTITIONTYPE_NTFS			- indicates that the structure is a <PARTITIONINFO_NTFS> structure;								*
;*								  4 bytes containing ASCII letters N,T,F,S														*
;*																																*
;********************************************************************************************************************************
PARTITIONTYPE_DRIVE		equ		000000000h
PARTITIONTYPE_EXTENDED	equ		000000001h
PARTITIONTYPE_NTFS		equ		05346544Eh

;********************************************************************************************************************************
;*																																*
;*	Structure: FILE																												*
;*																																*
;*	This structure defines an open file.  Files open on different media or partition types have their own structures with this	*
;*	as a header, e.g. <FILE_HARDDRIVE> and <FILE_NTFS>.																			*
;*																																*
;*	Members:																													*
;*		AccessLock		- <LOCKSTRUCT> to gain exclusive access to the file														*
;*		pFullPath		- address of a zero-terminated, unicode string containing the full path of the file, excluding			*
;*						  protocol, drive, and partition																		*
;*		pName			- pointer into the full path of the filename without the directories (so it doesn't need its own		*
;*						  allocation)																							*
;*		Protocol		- one of the <Data Protocol Constants>																	*
;*		Access			- some combination of the <File Access Constants>, indicating the access to the file					*
;*																																*
;********************************************************************************************************************************
FILE	STRUCT
	AccessLock		LOCKSTRUCT	<>
	pFullPath		DWORD	?
	pName			DWORD	?
	Protocol		DWORD	?
	Access			DWORD	?
FILE	ENDS

FILE_ALIGNMENT			equ		6			;FILE structures aligned to 64 bytes

PROTOCOL_HARDDRIVE		equ		000004448	;4 bytes containing ASCII letters H,D,NULL,NULL

;********************************************************************************************************************************
;*																																*
;*	Structure: FILE_HARDDRIVE																									*
;*																																*
;*	This structure defines an open file on a harddrive.  Files open on different partition types have their own structures with	*
;*	this as a header, e.g. <FILE_NTFS>.																							*
;*																																*
;*	Members:																													*
;*		Header			- the <FILE> structure component of this structure														*
;*		pPartition		- address of the <PARTITIONINFO> structure for the partition that this file is on						*
;*		OffsetInFile	- offset into the file at which read and write operations will next occur								*
;*																																*
;********************************************************************************************************************************
FILE_HARDDRIVE	STRUCT
	Header			FILE	<>
	pPartition		DWORD	?
	OffsetInFile	QWORD	?
FILE_HARDDRIVE	ENDS

.list
include	NTFS Driver.inc