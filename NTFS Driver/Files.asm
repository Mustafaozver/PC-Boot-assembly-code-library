;********************************************************************************************************************************
;*																																*
;*	File: Files.asm																												*
;*																																*
;*	This file defines file management functions of PwnOS.																		*
;*																																*
;*	See Also:																													*
;*		- <FilesInit.asm>																										*
;*		- <Files.inc>																											*
;*																																*
;*	Authors:																													*
;*		- Neil G. Dickson																										*
;*																																*
;********************************************************************************************************************************

CoreData		segment	use32
;ATADeviceInfo		ATADEVICEINFO	4 dup (<>)

pUppercase		DWORD			?

;HarddriveProtocol	word	"h","d",0
;USBProtocol			word	"u","s","b",0
;ProgramProtocol		word	"p","r","o","g",0
;HTTProtocol			word	"h","t","t","p",0
;FTProtocol			word	"f","t","p",0
CoreData		ends

CoreCode		segment	use32

;********************************************************************************************************************************
;*																																*
;*	Procedure: OpenFile																											*
;*																																*
;*	This procedure opens a file.																								*
;*																																*
;*	Parameters:																													*
;*		pName		- address of unicode filename																				*
;*		Access		- access options																							*
;*		Creation	- creation options																							*
;*		Flags		- miscellaneous																								*
;*																																*
;*	Returns:																													*
;*		- address of the <FILE> structure or NULL if the file doesn't exist or couldn't be opened								*
;*																																*
;<*******************************************************************************************************************************
OpenFile			proc	pName:PTR WORD,Access:DWORD,Creation:DWORD,Flags:DWORD
	push	esi
	mov		esi,pName
	xor		eax,eax
CheckNextForProtocol:
	lodsw
	test	ax,ax
	jz		NoProtocol
	cmp		ax,":"
	jne		CheckNextForProtocol
HasProtocol:
	mov		esi,pName
	lodsw
	or		ax,20h
	cmp		ax,"h"
	jne		ProtocolDoesntBeginWithH
	lodsw
	or		ax,20h
	cmp		ax,"d"
	jne		NotHarddriveProtocol
	lodsw
	sub		ax,"0"
	cmp		ax,4
	jae		InvalidHarddrive
IF sizeof ATADEVICEINFO NE 80
	.err	<Change line in OpenFile now that ATADEVICEINFO isn't 80 bytes>
ENDIF
	shl		eax,4
	lea		eax,[eax*4+eax]		;Note that the high order word is still 0
	lea		ecx,ATADeviceInfo[eax]
ASSUME ECX:PTR ATADEVICEINFO
	lodsw
	sub		ax,"0"
	cmp		ax,4
	jae		InvalidPartition
	mov		ecx,[ecx].pPartitions[eax*4]
NextChildPartition:
	test	ecx,ecx
	jz		InvalidPartition
ASSUME ECX:PTR PARTITIONINFO
	cmp		[ecx].PARTITIONINFO.PartitionType,PARTITIONTYPE_EXTENDED
	jne		FoundPartition
ASSUME ECX:PTR PARTITIONINFO_EXTENDED
	lodsw
	sub		ax,"0"
	cmp		ax,4
	jae		InvalidPartition
	mov		ecx,[ecx].pPartitions[eax*4]
	jmp		NextChildPartition

ASSUME ECX:PTR PARTITIONINFO
FoundPartition:
	lodsw
	cmp		ax,":"
	jne		InvalidPartition
SkipSlash:
	lodsw
	cmp		ax,"/"
	je		SkipSlash
	cmp		ax,"\"
	je		SkipSlash
	sub		esi,2
	cmp		[ecx].PartitionType,PARTITIONTYPE_NTFS
	jne		NotNTFSPartition
	invoke	OpenFileNTFS,ecx,esi,NULL,Access,Creation,Flags
	pop		esi
	ret
NoProtocol:
	invoke	GetCurrentDirectory
	test	eax,eax
	jz		NoCurrentDirectory
ASSUME EAX:PTR FILE
	cmp		[eax].Protocol,PROTOCOL_HARDDRIVE
	jne		NotHarddriveProtocol2
ASSUME EAX:PTR FILE_HARDDRIVE
	mov		ecx,[eax].pPartition
	cmp		[ecx].PartitionType,PARTITIONTYPE_NTFS
	jne		NotNTFSPartition2
	invoke	OpenFileNTFS,ecx,pName,eax,Access,Creation,Flags
	xor		ecx,ecx
	mov		[eax].Header.AccessLock.AccessFlags,ecx
	mov		[eax].Header.AccessLock.hThread,ecx
	mov		[eax].Header.AccessLock.pAccessList,ecx
	mov		[eax].Header.AccessLock.pWaitList,ecx
	pop		esi
	ret

NotNTFSPartition2:
NotHarddriveProtocol2:
NoCurrentDirectory:
NotNTFSPartition:
InvalidPartition:
InvalidHarddrive:
NotHarddriveProtocol:
ProtocolDoesntBeginWithH:
	xor		eax,eax
	pop		esi
	ret
ASSUME EAX:NOTHING,ECX:NOTHING
OpenFile			endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: GetFileSize																										*
;*																																*
;*	This procedure gets the size of an open file.																				*
;*																																*
;*	Parameters:																													*
;*		pFile		- address of <FILE> structure																				*
;*																																*
;*	Returns:																													*
;*		edx:eax		- size of the file in bytes, or -1 if the file has no particular size										*
;*																																*
;<*******************************************************************************************************************************
GetFileSize			proc	pFile:PTR FILE
	mov		edx,pFile
ASSUME EDX:PTR FILE
IF offset FILE.AccessLock NE 0
	.err	<Change line of GetFileSize now that FILE.AccessLock is not at the beginning of the FILE structure>
ENDIF
	invoke	GetLock,edx
	cmp		[edx].Protocol,PROTOCOL_HARDDRIVE
	jne		NotHarddriveProtocol
ASSUME EDX:PTR FILE_HARDDRIVE
	mov		ecx,[edx].pPartition
	cmp		[ecx].PARTITIONINFO.PartitionType,PARTITIONTYPE_NTFS
	jne		NotNTFSPartition
ASSUME EDX:PTR FILE_NTFS
	mov		edx,[edx].pDataAttrib
ASSUME EDX:PTR NTFSATTRIBHEADER
	cmp		[edx].NonResident?,FALSE
	jne		NonResidentAttribute
ASSUME EDX:PTR NTFSATTRIBHEADER_RES
	mov		eax,[edx].AttributeLength
	xor		edx,edx
IF offset FILE.AccessLock NE 0
	.err	<Change line of GetFileSize now that FILE.AccessLock is not at the beginning of the FILE structure>
ENDIF
	invoke	ReleaseLock,pFile
	ret
NonResidentAttribute:
ASSUME EDX:PTR NTFSATTRIBHEADER_NRES
	mov		eax,dword ptr [edx].RealSize
	mov		edx,dword ptr [edx].RealSize[4]
IF offset FILE.AccessLock NE 0
	.err	<Change line of GetFileSize now that FILE.AccessLock is not at the beginning of the FILE structure>
ENDIF
	invoke	ReleaseLock,pFile
	ret
ASSUME EDX:NOTHING
NotNTFSPartition:
NotHarddriveProtocol:
	or		eax,-1
	or		edx,-1
IF offset FILE.AccessLock NE 0
	.err	<Change line of GetFileSize now that FILE.AccessLock is not at the beginning of the FILE structure>
ENDIF
	invoke	ReleaseLock,pFile
	ret
GetFileSize			endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: ReadFile																											*
;*																																*
;*	This procedure reads data from an open file.																				*
;*																																*
;*	Parameters:																													*
;*		pFile			- address of <FILE> structure																			*
;*		pDestination	- address to which the data is to be read																*
;*		nBytes			- number of bytes to read																				*
;*																																*
;*	Returns:																													*
;*		- number of bytes read from the file																					*
;*																																*
;<*******************************************************************************************************************************
ReadFile			proc	pFile:PTR FILE,pDestination:DWORD,nBytes:DWORD
	mov		edx,pFile
ASSUME EDX:PTR FILE
IF offset FILE.AccessLock NE 0
	.err	<Change line of ReadFile now that FILE.AccessLock is not at the beginning of the FILE structure>
ENDIF
	invoke	GetLock,edx
	cmp		[edx].Protocol,PROTOCOL_HARDDRIVE
	jne		NotHarddriveProtocol
ASSUME EDX:PTR FILE_HARDDRIVE
	mov		ecx,[edx].pPartition
	cmp		[ecx].PARTITIONINFO.PartitionType,PARTITIONTYPE_NTFS
	jne		NotNTFSPartition
ASSUME EDX:PTR FILE_NTFS
	invoke	ReadFileNTFS,edx,pDestination,nBytes
IF offset FILE.AccessLock NE 0
	.err	<Change line of ReadFile now that FILE.AccessLock is not at the beginning of the FILE structure>
ENDIF
	invoke	ReleaseLock,pFile
	ret
ASSUME EDX:NOTHING
NotNTFSPartition:
NotHarddriveProtocol:
	xor		eax,eax
IF offset FILE.AccessLock NE 0
	.err	<Change line of ReadFile now that FILE.AccessLock is not at the beginning of the FILE structure>
ENDIF
	invoke	ReleaseLock,pFile
	ret
ReadFile			endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: CloseFile																										*
;*																																*
;*	This procedure closes an open file, freeing all of its resources.															*
;*																																*
;*	Parameters:																													*
;*		pFile			- address of <FILE> structure																			*
;*																																*
;<*******************************************************************************************************************************
CloseFile			proc	pFile:PTR FILE
	push	ebx
	push	esi
	mov		ebx,pFile
ASSUME EBX:PTR FILE
IF offset FILE.AccessLock NE 0
	.err	<Change line of CloseFile now that FILE.AccessLock is not at the beginning of the FILE structure>
ENDIF
	invoke	GetLock,ebx
	mov		esi,VA_USER_HEAP_MEMORY_HEADER
	mov		eax,VA_SYSTEM_HEAP_MEMORY_HEADER
	cmp		ebx,VA_SYSTEM_MEMORY
	cmovnb	esi,eax
ASSUME ESI:PTR HEAP_MEMORY_HEADER
	cmp		[ebx].Protocol,PROTOCOL_HARDDRIVE
	jne		NotHarddriveProtocol
ASSUME EBX:PTR FILE_HARDDRIVE
	mov		ecx,[ebx].pPartition
	cmp		[ecx].PARTITIONINFO.PartitionType,PARTITIONTYPE_NTFS
	jne		NotNTFSPartition
ASSUME EBX:PTR FILE_NTFS

	invoke	FreeMemory,[ebx].Header.Header.pFullPath,esi
	invoke	FreeMemory,[ebx].pFileRecord,esi
	cmp		[ebx].pDataAttrib,NULL
	je		NoDataAttribute
	invoke	FreeMemory,[ebx].pDataAttrib,esi
NoDataAttribute:
	cmp		[ebx].pClustersCached,NULL
	je		NoCache
	invoke	FreeMemory,[ebx].pClustersCached,esi
NoCache:

ASSUME EBX:NOTHING,ESI:NOTHING
NotNTFSPartition:
NotHarddriveProtocol:
	invoke	FreeMemory,pFile,esi
;Releasing the lock is meaningless now that the memory has been freed and the file has been closed
;IF offset FILE.AccessLock NE 0
;	.err	<Change line of CloseFile now that FILE.AccessLock is not at the beginning of the FILE structure>
;ENDIF
;	invoke	ReleaseLock,pFile
	pop		esi
	pop		ebx
	ret
CloseFile			endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: GetCurrentDirectory																								*
;*																																*
;*	Gets the current directory of the current thread.																			*
;*																																*
;*	*Not Implemented*																											*
;*																																*
;*	Returns:																													*
;*		- address of the <FILE> structure for the current directory of the current thread										*
;*																																*
;<*******************************************************************************************************************************
GetCurrentDirectory		proc
	xor		eax,eax
	ret
GetCurrentDirectory		endp

;>*******************************************************************************************************************************

;********************************************************************************************************************************
;*																																*
;*	Section: Gateway Functions of Files.asm																						*
;*																																*
;********************************************************************************************************************************

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: OpenFileU																										*
;*																																*
;*	Gateway function for <OpenFile>																								*
;*																																*
;*	*TODO:* Check parameters.																									*
;*																																*
;<*******************************************************************************************************************************
OpenFileU		proc
	mov		ecx,[esp][12]	;Privilege Level 3 esp, and ss should be the same as ds
	invoke	OpenFile,dword ptr [ecx][0],dword ptr [ecx][4],dword ptr [ecx][8],dword ptr [ecx][12]
	ret
OpenFileU		endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: GetFileSizeU																										*
;*																																*
;*	Gateway function for <GetFileSize>																							*
;*																																*
;*	*TODO:* Check parameter.																									*
;*																																*
;<*******************************************************************************************************************************
GetFileSizeU		proc
	mov		ecx,[esp][12]	;Privilege Level 3 esp, and ss should be the same as ds
	invoke	GetFileSize,dword ptr [ecx][0]
	ret
GetFileSizeU		endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: ReadFileU																										*
;*																																*
;*	Gateway function for <ReadFile>																								*
;*																																*
;*	*TODO:* Check parameters.																									*
;*																																*
;<*******************************************************************************************************************************
ReadFileU		proc
	mov		ecx,[esp][12]	;Privilege Level 3 esp, and ss should be the same as ds
	invoke	ReadFile,dword ptr [ecx][0],dword ptr [ecx][4],dword ptr [ecx][8]
	ret
ReadFileU		endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: WriteFileU																										*
;*																																*
;*	Gateway function for <WriteFile>																							*
;*																																*
;*	*Not Implemented*																											*
;*																																*
;<*******************************************************************************************************************************
WriteFileU		proc
	mov		ecx,[esp][12]	;Privilege Level 3 esp, and ss should be the same as ds
	
	
	
	
	ret
WriteFileU		endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: CloseFileU																										*
;*																																*
;*	Gateway function for <CloseFile>																							*
;*																																*
;*	*TODO:* Check parameter.																									*
;*																																*
;<*******************************************************************************************************************************
CloseFileU		proc
	mov		ecx,[esp][12]	;Privilege Level 3 esp, and ss should be the same as ds
	invoke	CloseFile,dword ptr [ecx][0]
	ret
CloseFileU		endp

CoreCode		ends

include		NTFS Driver.asm
