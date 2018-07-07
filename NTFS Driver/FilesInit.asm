;********************************************************************************************************************************
;*																																*
;*	File: FilesInit.asm																											*
;*																																*
;*	This file defines initialization code for the file management data of PwnOS.												*
;*																																*
;*	See Also:																													*
;*		- <Files.asm>																											*
;*		- <Files.inc>																											*
;*																																*
;*	Authors:																													*
;*		- Neil G. Dickson																										*
;*																																*
;********************************************************************************************************************************

InitNTFSPartition		proto	nDrive:DWORD,pParent:DWORD,nPartitionTimes4:DWORD,FirstSector:DWORD,nSectors:DWORD,Flags:DWORD
InitExtendedPartition	proto	nDrive:DWORD,pParent:DWORD,nPartitionTimes4:DWORD,FirstSector:DWORD,nSectors:DWORD,Flags:DWORD


CoreInit		segment	use32

;********************************************************************************************************************************
;*																																*
;*	Procedure: InitFiles																										*
;*																																*
;*	This procedure initializes the <Core> file management data.  It depends on the <Memory> section being initialized, except	*
;*	pagefile data, because that's dependent on this.																			*
;*																																*
;<*******************************************************************************************************************************
InitFiles	proc
 LOCAL nDrive:DWORD
 LOCAL pDrive:PTR ATADEVICEINFO
	push	ebx
	push	esi
	sub		esp,ATA_SECTOR_SIZE
	mov		ebx,esp
	mov		nDrive,0
NextDrive:
	invoke	ATAIsValidDevice,nDrive
	test	eax,eax
	jz		SkipToNextDrive
	mov		pDrive,eax
	invoke	ATAReadSectors,ebx,nDrive,0,0,1
	xor		esi,esi
NextPartition:
	lea		ecx,[MBR_ENTRY0_OFFSET][esi*4][ebx]
ASSUME ECX:PTR PARTITIONENTRY
IF sizeof PARTITIONENTRY NE 16
	.err	<Change lines in InitFiles now that PARTITIONENTRY is not 16 bytes.>
ENDIF
	mov		al,[ecx].PartitionType
	cmp		al,MBR_PARTTYPE_EXTENDED_LBA
	je		ExtendedPartition
	cmp		al,MBR_PARTTYPE_EXTENDED
	je		ExtendedPartition
	cmp		al,MBR_PARTTYPE_NTFS
	jne		SkipToNextPartition
NTFSPartition:
	invoke	InitNTFSPartition,nDrive,pDrive,esi,[ecx].FirstSector,[ecx].NumSectors,[ecx].IsBootable
	jmp		FillInPartition
ExtendedPartition:
	invoke	InitExtendedPartition,nDrive,pDrive,esi,[ecx].FirstSector,[ecx].NumSectors,[ecx].IsBootable
FillInPartition:
	mov		edx,pDrive
	mov		[edx].ATADEVICEINFO.pPartitions[esi],eax
	
SkipToNextPartition:
	add		esi,4
	cmp		esi,16		;There are 4 possible partitions, and each pointer takes up 4 bytes
	jne		NextPartition
	
SkipToNextDrive:
	inc		nDrive
	cmp		nDrive,4	;There are 4 possible ATA drives
	jne		NextDrive
	
	add		esp,ATA_SECTOR_SIZE
	pop		esi
	pop		ebx
	ret
ASSUME ECX:NOTHING
InitFiles	endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: InitNTFSPartition																								*
;*																																*
;*	This procedure initializes the data for an NTFS partition.																	*
;*																																*
;*	Things that this needs to initialize:																						*
;*		- a new PARTITIONINFO_NTFS structure																					*
;*			- the contained PARTITIONINFO structure and miscellaneous NTFS data													*
;*			- a new FILE_NTFS structure for the MFT file																		*
;*				- the MFT file record																							*
;*			- a new FILE_NTFS structure for the root file and its data															*
;*				- the root file record																							*
;*																																*
;*	Parameters:																													*
;*		nDrive				- number of the ATA drive (from 0 to 3)																*
;*		pParent				- address of the parent <ATADEVICEINFO> or <PARTITIONINFO> structure								*
;*		nPartitionTimes4	- number of this partition within the parent partition or drive										*
;*		FirstSector			- first sector of this partition on the drive														*
;*		nSectors			- number of sectors in this partition																*
;*		Flags				- miscellaneous flags, e.g. PARTITIONINFO_FLAG_BOOTABLE												*
;*																																*
;*	Returns:																													*
;*		- address of new <PARTITIONINFO_NTFS> with its data initialized															*
;*																																*
;<*******************************************************************************************************************************
InitNTFSPartition		proc	nDrive:DWORD,pParent:DWORD,nPartitionTimes4:DWORD,FirstSector:DWORD,nSectors:DWORD,Flags:DWORD
	push	ebx
	push	esi
;********************************************************************************************************************************
;*	create the PARTITIONINFO_NTFS structure																						*
;********************************************************************************************************************************
	invoke	AllocateAlignedMemory,sizeof PARTITIONINFO_NTFS,PARTITIONINFO_ALIGNMENT,VA_SYSTEM_HEAP_MEMORY_HEADER
	mov		ebx,eax
ASSUME EBX:PTR PARTITIONINFO_NTFS
;********************************************************************************************************************************
;*	fill in the PARTITIONINFO structure																							*
;********************************************************************************************************************************
	mov		eax,nDrive
	mov		[ebx].Header.PartitionType,PARTITIONTYPE_NTFS
	add		eax,DEVICENUM_ATA0
	mov		ecx,pParent
	mov		[ebx].Header.DeviceNum,eax
	mov		[ebx].Header.pParent,ecx
	test	Flags,MBR_PARTITION_ACTIVE
	jz		NotBootable
	mov		[ebx].Header.Flags,PARTITIONINFO_FLAG_BOOTABLE
	jmp		BootFlagSet
NotBootable:
	mov		[ebx].Header.Flags,0
BootFlagSet:
	mov		eax,dword ptr FirstSector
	xor		edx,edx
	mov		dword ptr [ebx].Header.FirstSector,eax
	mov		dword ptr [ebx].Header.FirstSector[4],edx
	mov		dword ptr [ebx].Header.Synonym,edx
	mov		dword ptr [ebx].Header.Synonym[4],edx
;********************************************************************************************************************************
;*	read in the first sector of the partition to get the partition data															*
;********************************************************************************************************************************
IF ATA_SECTOR_SIZE NE 200h
	.err	<Change line in InitNTFSPartition now that ATA_SECTOR_SIZE is not 200h>
ENDIF
	invoke	AllocateAlignedMemory,ATA_SECTOR_SIZE,9,VA_SYSTEM_HEAP_MEMORY_HEADER	;log2(ATA_SECTOR_SIZE) = 9
	mov		esi,eax
	invoke	ATAReadSectors,esi,nDrive,FirstSector,0,1
ASSUME ESI:PTR NTFSBOOTSTRUCT
	
;********************************************************************************************************************************
;*	fill in the PARTITIONINFO_NTFS structure's miscellaneous data																*
;********************************************************************************************************************************
	mov		eax,dword ptr [esi].nSectors
	mov		edx,dword ptr [esi].nSectors[4]
	mov		dword ptr [ebx].Header.nSectors,eax
	mov		eax,dword ptr [esi].LCN$MFT
	mov		dword ptr [ebx].Header.nSectors[4],edx
	mov		edx,dword ptr [esi].LCN$MFT[4]
	mov		dword ptr [ebx].LCN$MFT,eax
	mov		dword ptr [ebx].LCN$MFT[4],edx
	
	mov		cl,byte ptr [esi].ClusPerFILERec
	mov		ch,byte ptr [esi].ClusPerINDXBuf
	xor		eax,eax
	mov		al,[esi].SectorsPerClus


IF offset PARTITIONINFO_NTFS.ClusPerINDXBuf - offset PARTITIONINFO_NTFS.ClusPerFILERec NE 1
	.err	<InitNTFSPartition depends on PARTITIONINFO_NTFS.ClusPerINDXBuf being right after PARTITIONINFO_NTFS.ClusPerFILERec>
ENDIF
	mov		word ptr [ebx].ClusPerFILERec,cx	;also sets [ebx].ClusPerINDXBuf
	mov		[ebx].SectorsPerClus,al
	
;********************************************************************************************************************************
;*	find and read in the MFT file record																						*
;********************************************************************************************************************************
	test	cl,cl			;check if ClusPerFILERec is negative or positive
	js		SignedBytePower
	movzx	ecx,cl
	mul		ecx
	push	eax
IF ATA_SECTOR_SIZE NE 200h
	.err	<Change line in InitNTFSPartition now that ATA_SECTOR_SIZE is not 200h>
ENDIF
	shl		eax,9
	invoke	AllocateAlignedMemory,eax,PARTITIONINFO_ALIGNMENT,VA_SYSTEM_HEAP_MEMORY_HEADER
	mov		[ebx].pMFTFileRecord,eax
	
	mov		eax,dword ptr [ebx].LCN$MFT[4]		;calculate LCN$MFT * SectorsPerClus
ASSUME ESI:NOTHING
	movzx	esi,[ebx].SectorsPerClus
	mul		esi
	mov		ecx,eax
	mov		eax,dword ptr [ebx].LCN$MFT
	mul		esi
	add		edx,ecx
	add		eax,FirstSector
	adc		edx,0
	
	pop		esi
	
	invoke	ATAReadSectors,[ebx].pMFTFileRecord,nDrive,eax,edx,esi
	
	
	
	.err	<Finish this!!!!!!>
	echo	<Copy code from MountNTFSPartition in Boot.asm>
	
	
	
	
	
	pop		esi
	pop		ebx
	ret
ASSUME EBX:NOTHING,ESI:NOTHING
InitNTFSPartition		endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: InitExtendedPartition																							*
;*																																*
;*	This procedure initializes the data for an extended partition.																*
;*																																*
;*	Parameters:																													*
;*		nDrive				- number of the ATA drive (from 0 to 3)																*
;*		pParent				- address of the parent <ATADEVICEINFO> or <PARTITIONINFO> structure								*
;*		nPartitionTimes4	- number of this partition within the parent partition or drive										*
;*		FirstSector			- first sector of this partition on the drive														*
;*		nSectors			- number of sectors in this partition																*
;*		Flags				- miscellaneous flags, e.g. PARTITIONINFO_FLAG_BOOTABLE												*
;*																																*
;*	Returns:																													*
;*		- address of new <PARTITIONINFO_EXTENDED> with its data initialized														*
;*																																*
;<*******************************************************************************************************************************
InitExtendedPartition	proc	nDrive:DWORD,pParent:DWORD,nPartitionTimes4:DWORD,FirstSector:DWORD,nSectors:DWORD,Flags:DWORD
	invoke	AllocateAlignedMemory,sizeof PARTITIONINFO_EXTENDED,PARTITIONINFO_ALIGNMENT,VA_SYSTEM_HEAP_MEMORY_HEADER
	
	.err	<Finish this!!!!!!>

	ret
InitExtendedPartition	endp

CoreInit		ends