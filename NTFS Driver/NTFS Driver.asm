;********************************************************************************************************************************
;*																																*
;*	File: NTFS Driver.asm																										*
;*																																*
;*	This file defines the NTFS driver of PwnOS.																					*
;*																																*
;*	See Also:																													*
;*		- <NTFS Driver.inc>																										*
;*		- <NTFS.inc>																											*
;*		- <Files.asm>																											*
;*																																*
;*	Authors:																													*
;*		- Neil G. Dickson																										*
;*																																*
;********************************************************************************************************************************

SearchNTFSDirectory		proto	pPartition:PTR PARTITIONINFO_NTFS,pName:PTR WORD,pDirFileHeader:PTR NTFSFILEHEADER,pIndexScratch:DWORD
GetNTFSFileRecord		proto	pDest:DWORD,pPartition:PTR PARTITIONINFO_NTFS,FileRecNumLow:DWORD,FileRecNumHigh:DWORD
VirtualClusNumToSector	proto	pPartition:PTR PARTITIONINFO_NTFS,VCNLow:DWORD,VCNHigh:DWORD,pAttribute:DWORD
LogicalClusNumToSector	proto	pPartition:PTR PARTITIONINFO_NTFS,LCNLow:DWORD,LCNHigh:DWORD
ReadVirtualClusters		proto	pPartition:PTR PARTITIONINFO_NTFS,VCNLow:DWORD,VCNHigh:DWORD,pAttribute:DWORD,pDestination:DWORD,nClusters:DWORD


CoreCode		segment	use32

;********************************************************************************************************************************
;*																																*
;*	Procedure: OpenFileNTFS																										*
;*																																*
;*	This procedure opens a file from an NTFS partition.  It should only be called from <OpenFile>.								*
;*																																*
;*	*TODO:* Add handling for Access value and Creation value.																	*
;*																																*
;*	Parameters:																													*
;*		pPartition		- address of <PARTITIONINFO_NTFS> structure for the NTFS partition										*
;*		pName			- address of unicode filename with no preceding protocol												*
;*		pDirectory		- address of <FILE> structure for the directory to which the filename is relative, or NULL if absolute	*
;*		Access			- access options																						*
;*		Creation		- creation options																						*
;*		Flags			- miscellaneous																							*
;*																																*
;*	Local Variables:																											*
;*		pHeap			- address of the heap on which to allocate memory														*
;*		MFTRecordNum	- <NTFSMFTREF> to keep track of the MFT record number of the file found									*
;*																																*
;*	Returns:																													*
;*		- address of the <FILE> structure or NULL if the file doesn't exist or couldn't be opened								*
;*																																*
;<*******************************************************************************************************************************
OpenFileNTFS	proc	pPartition:PTR PARTITIONINFO_NTFS,pName:PTR WORD,pDirectory:PTR FILE,Access:DWORD,Creation:DWORD,Flags:DWORD
 LOCAL MFTRecordNum:NTFSMFTREF
 LOCAL pHeap:PTR HEAP_MEMORY_HEADER
	push	esi
	push	edi
	push	ebx
	invoke	AllocatePages,NULL,2,MEM_COMMIT,PAGE_EXECUTE_READWRITE or PAGE_NOACCESS	;Allocate 2 pages: 1 for index scratch, 1 for file record scratch
	mov		edi,eax
	mov		ebx,pPartition
ASSUME EBX:PTR PARTITIONINFO_NTFS
	mov		esi,pName
	lodsw
	test	ax,ax
	jz		Invalid
	cmp		ax,"/"
	je		FromRoot
	cmp		ax,"\"
	je		FromRoot
	sub		esi,2
	mov		ecx,pDirectory
	test	ecx,ecx
	jz		FromRoot
	mov		ecx,[ecx].FILE_NTFS.pFileRecord
	jmp		HaveDirectoryHeader
FromRoot:
	mov		ecx,[ebx].pRootFileRecord
HaveDirectoryHeader:
	invoke	SearchNTFSDirectory,ebx,esi,ecx,edi		;Find the MFT record number of the file or next subdirectory
	test	eax,eax
	jnz		FoundNext
	test	edx,edx
	jz		NotFound
FoundNext:
	and		edx,0FFFFh
	mov		dword ptr MFTRecordNum,eax
	mov		dword ptr MFTRecordNum[4],edx
	lea		ecx,[edi+10000h]
	invoke	GetNTFSFileRecord,ecx,ebx,eax,edx		;Read the MFT file record into memory
	lea		ecx,[edi+10000h]
NextCharacter:										;Move to the character of the name of the file or next subdirectory 
	lodsw											;	Move to the next character
	cmp		ax,"/"									;	If just passed a "/" character,
	je		HaveDirectoryHeader						;		another directory
	cmp		ax,"\"									;	If just passed a "\" character,
	je		HaveDirectoryHeader						;		another directory
	test	ax,ax									;	If not at the end, 
	jnz		NextCharacter							;		keep moving
													;Now have MFT file record of the desired file in memory
	mov		eax,VA_USER_HEAP_MEMORY_HEADER			;Select the heap on which to allocate the memory
	mov		edx,VA_SYSTEM_HEAP_MEMORY_HEADER		;
	test	Flags,OPENFILE_FLAG_SYSTEM				;
	cmovnz	eax,edx									;
	mov		pHeap,eax								;
	invoke	AllocateAlignedMemory,[ecx].NTFSFILEHEADER.RealSize,FILE_NTFS_RECORD_ALIGNMENT,eax	;Allocate memory for a copy of the MFT file record
	push	eax
	push	esi
	push	edi
	lea		esi,[edi+10000h]
	mov		ecx,[esi].NTFSFILEHEADER.RealSize
	mov		edi,eax
	mov		eax,esp			;save xmm0-xmm3 on the stack
	and		esp,not 3Fh		;aligned to 40h bytes
	sub		esp,40h			;40h bytes of data
	movdqa	[esp][00h],xmm0	;
	movdqa	[esp][10h],xmm1	;
	movdqa	[esp][20h],xmm2	;
	movdqa	[esp][30h],xmm3	;
NextCopyFileHeader:														;Copy the MFT file record
	movdqa	xmm0,[esi][00h]
	movdqa	xmm1,[esi][10h]
	movdqa	xmm2,[esi][20h]
	movdqa	xmm3,[esi][30h]
	movdqa	[edi][00h],xmm0
	movdqa	[edi][10h],xmm1
	movdqa	[edi][20h],xmm2
	movdqa	[edi][30h],xmm3
	add		esi,40h
	add		edi,40h
	sub		ecx,40h
	ja		NextCopyFileHeader
	movdqa	xmm0,[esp][00h]	;restore xmm0-xmm3
	movdqa	xmm1,[esp][10h]	;
	movdqa	xmm2,[esp][20h]	;
	movdqa	xmm3,[esp][30h]	;
	mov		esp,eax			;release from stack
	
	pop		edi
	invoke	FreePages,edi,2												;Free the 2 scratch pages
	invoke	AllocateAlignedMemory,sizeof FILE_NTFS,FILE_ALIGNMENT,pHeap	;Allocate the FILE_NTFS structure
	mov		ebx,eax
ASSUME EBX:PTR FILE_NTFS
	mov		esi,pDirectory
ASSUME ESI:PTR FILE
	test	esi,esi														;Find the length of the full path to allocate it
	jz		NameLengthFromRoot
	mov		ecx,[esi].pFullPath
NextDirNameCount:
	test	word ptr [ecx],-1
	jz		EndOfDirNameCount
	add		ecx,2
	jmp		NextDirNameCount
EndOfDirNameCount:
	sub		ecx,[esi].pFullPath
	pop		edx			;formerly esi for moving along name, so it's at the end of the name
	sub		edx,pName	;now edx is the size in bytes of the name (plus terminating 0), excluding the directory name
	add		edx,ecx		;and now it's the size in bytes of the full path (plus terminating 0, but minus the "/" between the two names)
	add		edx,2		;now it's the size in bytes of the full path (plus terminating 0)
	jmp		HavePathLength
NameLengthFromRoot:
	pop		edx
	sub		edx,pName
HavePathLength:
	invoke	AllocateMemory,edx,pHeap									;Allocate the memory to hold the full path
	mov		[ebx].Header.Header.pFullPath,eax
	test	esi,esi
	jz		NameCopyFromRoot
	mov		ecx,[esi].pFullPath											;Copy the full path
NextDirNameCopy:
	mov		dx,word ptr [ecx]
	add		ecx,2
	test	dx,dx
	jz		EndOfDirNameCopy
	mov		word ptr [eax],dx
	add		eax,2
	jmp		NextDirNameCopy
EndOfDirNameCopy:
	mov		word ptr [eax],"/"
	add		eax,2
NameCopyFromRoot:
	xor		edi,edi
	mov		ecx,pName
NextNameCopy:
	mov		dx,word ptr [ecx]
	add		ecx,2
	mov		word ptr [eax],dx
	add		eax,2
	cmp		dx,"/"
	cmove	edi,eax
	cmp		dx,"\"
	cmove	edi,eax
	test	dx,dx			;comparison at end of loop so that the terminating 0 is copied too
	jnz		NextNameCopy
	
	test	edi,edi
	jz		FileInRootDir
	add		edi,2			;currently on the "/", so move one character toward the end
	jmp		HaveNameOffsetInPath
FileInRootDir:
	mov		edi,[ebx].Header.Header.pFullPath
HaveNameOffsetInPath:
	mov		[ebx].Header.Header.pName,edi
	
	mov		eax,pPartition
	mov		edx,dword ptr MFTRecordNum
	mov		edi,dword ptr MFTRecordNum[4]
	xor		ecx,ecx
	mov		[ebx].Header.Header.Protocol,PROTOCOL_HARDDRIVE
	mov		[ebx].Header.pPartition,eax
	mov		dword ptr [ebx].Header.OffsetInFile,ecx		;start at beginning of file (offset 0)
	mov		dword ptr [ebx].Header.OffsetInFile[4],ecx	;
	mov		dword ptr [ebx].FileRef,edx
	mov		dword ptr [ebx].FileRef[4],edi
	pop		esi
	mov		[ebx].pFileRecord,esi
ASSUME ESI:PTR NTFSFILEHEADER
	xor		eax,eax
	mov		ax,[esi].OffAttributes
	add		esi,eax
ASSUME ESI:PTR NTFSATTRIBHEADER
NextAttribute:
	cmp		[esi].AttributeType,NTFSATTRIBTYPE_DATA
	je		FoundDataAttributeHeader
	cmp		[esi].AttributeType,NTFSATTRIBTYPE_INDEXROOT
	je		FoundDataAttributeHeader
	cmp		[esi].AttributeType,NTFSATTRIBTYPE_END_MARKER
	je		NoDataAttributeFound
	add		esi,[esi].ThisLength
	jmp		NextAttribute
NoDataAttributeFound:
	xor		esi,esi		;if no data attribute or index root attribute, set it to null
FoundDataAttributeHeader:
	or		eax,-1
	xor		edx,edx
	mov		[ebx].pDataAttrib,esi
	mov		dword ptr [ebx].VCNCache,eax			;VCN of cache is -1 indicating no cache
	mov		dword ptr [ebx].VCNCache[4],eax			;
	mov		dword ptr [ebx].OffsetOfCache,eax		;Offset in file of cache is -1 indicating no cache
	mov		dword ptr [ebx].OffsetOfCache[4],eax	;
	mov		[ebx].pClustersCached,edx				;Address of cache is null indicating no cache
	mov		[ebx].nClustersCached,edx				;Number of clusters in cache is 0 indicating no cache
	
	mov		eax,ebx
	pop		ebx
	pop		edi
	pop		esi
	ret
ASSUME EBX:NOTHING,ESI:NOTHING
NotFound:
Invalid:
	pop		ebx
	pop		edi
	pop		esi
	xor		eax,eax
	ret
OpenFileNTFS	endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: ReadFileNTFS																										*
;*																																*
;*	This procedure reads data from an open file on an NTFS partition.															*
;*																																*
;*	Parameters:																													*
;*		pFile			- address of <FILE_NTFS> structure																		*
;*		pDestination	- address to which the data is to be read																*
;*		nBytes			- number of bytes to read																				*
;*																																*
;*	Local Variables:																											*
;*		nBytesPerCluster	- size of a cluster in bytes																		*
;*		nBytesInCache		- size of the file's cache in bytes																	*
;*																																*
;*	Returns:																													*
;*		- number of bytes read from the file																					*
;*																																*
;<*******************************************************************************************************************************
ReadFileNTFS			proc	pFile:PTR FILE_NTFS,pDestination:DWORD,nBytes:DWORD
 LOCAL	nBytesInCache:DWORD
 LOCAL	nBytesPerCluster:DWORD
	push	esi
	push	ebx
	push	edi
	mov		esi,pFile
ASSUME ESI:PTR FILE_NTFS
	mov		eax,dword ptr [esi].Header.OffsetInFile
	mov		edx,dword ptr [esi].Header.OffsetInFile[4]
	add		eax,nBytes
	adc		edx,0
	
	mov		ebx,[esi].pDataAttrib
	test	ebx,ebx
	jz		NoDataAttribute
ASSUME EBX:PTR NTFSATTRIBHEADER
	cmp		[ebx].AttributeType,NTFSATTRIBTYPE_DATA
	jne		NoDataAttribute
	cmp		[ebx].NonResident?,FALSE
	jne		NonResidentAttribute
	
ASSUME EBX:PTR NTFSATTRIBHEADER_RES				;Resident data attribute
	test	edx,edx								;	Make sure that nBytes doesn't make the read go beyond the end of the file
	jnz		nBytesTooLargeResident
	cmp		eax,[ebx].AttributeLength
	jbe		nBytesNotTooLargeResident
nBytesTooLargeResident:
	mov		ecx,[ebx].AttributeLength
	sub		ecx,dword ptr [esi].Header.OffsetInFile
	mov		nBytes,ecx
nBytesNotTooLargeResident:
	mov		edi,pDestination					;	Just copy the data from memory
	xor		esi,esi
	mov		si,[ebx].AttributeOffset
	add		esi,ebx
	push	ecx
	shr		ecx,2
	jz		SmallResidentRead
	rep	movsd
SmallResidentRead:
	pop		ecx
	and		ecx,3h
	jz		DoneRead
	rep	movsb
	jmp		DoneRead
	
NonResidentAttribute:							;Non-resident data attribute
ASSUME EBX:PTR NTFSATTRIBHEADER_NRES
	cmp		edx,dword ptr [ebx].RealSize[4]		;	Make sure that nBytes doesn't make the read go beyond the end of the file
	ja		nBytesTooLargeNonResident
	jb		nBytesNotTooLargeNonResident
	cmp		eax,dword ptr [ebx].RealSize
	jbe		nBytesNotTooLargeNonResident
nBytesTooLargeNonResident:
	mov		ecx,dword ptr [ebx].RealSize		;		nBytes can't be larger than 2^32-1, so only need to subtract lower dwords to get length to end
	sub		ecx,dword ptr [esi].Header.OffsetInFile
	mov		nBytes,ecx
nBytesNotTooLargeNonResident:
	
	mov		edi,[esi].Header.pPartition
ASSUME EDI:PTR PARTITIONINFO_NTFS
	xor		eax,eax
	mov		al,[edi].SectorsPerClus
IF ATA_SECTOR_SIZE NE 200h
	.err	<Change lines in ReadFileNTFS now that ATA_SECTOR_SIZE is not 200h>
ENDIF
	shl		eax,9
	mov		nBytesPerCluster,eax	;save number of bytes per cluster, and HasCache depends on it being in eax
	cmp		[esi].pClustersCached,NULL
	jne		HasCache								;If the file has no cache
	mov		[esi].nClustersCached,NTFS_NUM_CACHED_CLUSTERS
	mul		[esi].nClustersCached
	mov		nBytesInCache,eax						;	save size of cache
	mov		ecx,VA_USER_HEAP_MEMORY_HEADER			;	Select the heap on which to allocate the memory
	mov		edx,VA_SYSTEM_HEAP_MEMORY_HEADER		;
	cmp		pFile,VA_SYSTEM_MEMORY					;
	cmovnb	ecx,edx									;
	invoke	AllocateAlignedMemory,eax,9,ecx			;	Allocate a cache of NTFS_NUM_CACHED_CLUSTERS clusters, aligned to sector size
	mov		[esi].pClustersCached,eax
	jmp		BeginningNotInCache
	
HasCache:											;Else (file has cache already)
	mul		[esi].pClustersCached					;	this depends on nBytesPerCluster being in eax from above
	mov		nBytesInCache,eax						;	save size of cache
	mov		ecx,dword ptr [esi].OffsetOfCache		;	Check to see if the beginning of the read is in the cache
	mov		edx,dword ptr [esi].OffsetOfCache[4]
	cmp		dword ptr [esi].Header.OffsetInFile[4],edx
	jb		BeginningNotInCache
	ja		BeginningPossiblyInCache
	cmp		dword ptr [esi].Header.OffsetInFile,ecx
	jb		BeginningNotInCache
	je		BeginningInCache
BeginningPossiblyInCache:
	add		ecx,nBytesInCache
	adc		edx,0
	cmp		dword ptr [esi].Header.OffsetInFile[4],edx
	jb		BeginningInCache
	ja		BeginningNotInCache
	cmp		dword ptr [esi].Header.OffsetInFile,ecx
	jb		BeginningInCache

BeginningNotInCache:
	mov		ecx,nBytesPerCluster					;Figure out what virtual cluster is the first to be read
	push	ebx
	mov		eax,dword ptr [esi].Header.OffsetInFile[4]	;take into account chance of VCN>=2^32
	xor		edx,edx										;so need to avoid divide overflow
	div		ecx											;
	mov		ebx,eax										;ebx has upper dword of VCN
	mov		eax,dword ptr [esi].Header.OffsetInFile		;edx:eax has byte# mod (nBytesPerCluster*2^32)
	div		ecx											;ebx:eax has VCN, edx has byte offset within cluster (byte# mod nBytesPerCluster)
	mov		dword ptr [esi].VCNCache,eax
	mov		dword ptr [esi].VCNCache[4],ebx
	mov		ecx,ebx
	pop		ebx
	push	edx		;save offset in the cluster, because that can be used later to find the file offset of the beginning of the first cached cluster
	invoke	ReadVirtualClusters,edi,eax,ecx,ebx,[esi].pClustersCached,[esi].nClustersCached
	pop		ecx		;offset in cluster
	mov		eax,dword ptr [esi].Header.OffsetInFile
	mov		edx,dword ptr [esi].Header.OffsetInFile[4]
	sub		eax,ecx
	sbb		edx,0
	mov		dword ptr [esi].OffsetOfCache,eax
	mov		dword ptr [esi].OffsetOfCache[4],edx
	jmp		BeginningInCacheHaveOffset
	
BeginningInCache:
	mov		ecx,dword ptr [esi].Header.OffsetInFile	;The cache is less than 2^32 bytes, so only need to subtract low dwords to get offset in cache
	sub		ecx,dword ptr [esi].OffsetOfCache		;
BeginningInCacheHaveOffset:
	mov		eax,nBytesInCache	;eax = nBytesInCache - offset of read in cache
	sub		eax,ecx				;
NewCacheLoop:
	cmp		eax,nBytes			;eax = min(nBytesInCache - offset of read in cache, nBytes)
	cmova	eax,nBytes			;
	push	edi
	mov		edi,pDestination
	push	esi
	mov		esi,[esi].pClustersCached
ASSUME ESI:NOTHING
	add		esi,ecx
	mov		ecx,eax
	push	ecx
	shr		ecx,2
	jz		SmallNonResidentRead
	rep	movsd
SmallNonResidentRead:
	pop		ecx
	mov		eax,ecx
	and		ecx,3h
	jz		DoneSingleCacheRead
	rep	movsb
DoneSingleCacheRead:
	pop		esi
ASSUME ESI:PTR FILE_NTFS
	mov		pDestination,edi
	pop		edi
	add		dword ptr [esi].Header.OffsetInFile,eax
	adc		dword ptr [esi].Header.OffsetInFile[4],0
	sub		nBytes,eax
	jz		DoneRead
	mov		eax,dword ptr [esi].VCNCache
	mov		ecx,dword ptr [esi].VCNCache[4]
	add		eax,[esi].nClustersCached
	adc		ecx,0
	mov		dword ptr [esi].VCNCache,eax
	mov		dword ptr [esi].VCNCache[4],ecx
	invoke	ReadVirtualClusters,edi,eax,ecx,ebx,[esi].pClustersCached,[esi].nClustersCached
	mov		eax,dword ptr [esi].Header.OffsetInFile
	mov		ecx,dword ptr [esi].Header.OffsetInFile[4]
	mov		dword ptr [esi].OffsetOfCache,eax
	mov		dword ptr [esi].OffsetOfCache[4],ecx
	mov		eax,nBytesInCache
	jmp		NewCacheLoop
	
DoneRead:
	mov		eax,nBytes
	pop		edi
	pop		ebx
	pop		esi
	ret
ASSUME EBX:NOTHING,ESI:NOTHING,EDI:NOTHING
NoDataAttribute:
	pop		edi
	pop		ebx
	pop		esi
	xor		eax,eax
	ret
ReadFileNTFS			endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: SearchNTFSDirectory																								*
;*																																*
;*	This procedure finds a file (or directory) in an NTFS directory.  It should only be called from <OpenFileNTFS>.				*
;*																																*
;*	Parameters:																													*
;*		pPartition		- address of <PARTITIONINFO_NTFS> structure for the NTFS partition										*
;*		pName			- address of unicode filename;																			*
;*						  in case pointing to the middle of a path, the function considers "\", "/", or 0 to be the name end	*
;*		pDirFileHeader	- address of <NTFSFILEHEADER> structure for the directory to search										*
;*		pIndexScratch	- address of I/O scratch memory (must be at least cluster size)											*
;*																																*
;*	Local Variables:																											*
;*		pIndexRoot		- address of index root attribute structure																*
;*		pIndexAlloc		- address of index allocation attribute structure														*
;*																																*
;*	Returns:																													*
;*		edx:eax	- the <NTFSMFTREF> (eax is low, edx is high), including sequence number, or 0 if file not found					*
;*																																*
;<*******************************************************************************************************************************
SearchNTFSDirectory		proc	pPartition:PTR PARTITIONINFO_NTFS,pName:PTR WORD,pDirFileHeader:PTR NTFSFILEHEADER,pIndexScratch:DWORD
 LOCAL	pIndexAlloc:DWORD
 LOCAL	pIndexRoot:DWORD
	push	esi
	push	edi
	push	ebx
	mov		esi,pDirFileHeader
ASSUME ESI:PTR NTFSFILEHEADER
	xor		eax,eax
	mov		pIndexRoot,eax
	mov		pIndexAlloc,eax
	mov		ax,[esi].OffAttributes
ASSUME EAX:PTR NTFSATTRIBHEADER
NextAttribute:
;	GfxOutputVar	"Attrib type: ",[esi][eax].AttributeType
	cmp		[esi][eax].AttributeType,NTFSATTRIBTYPE_END_MARKER
	je		NotFound
	cmp		[esi][eax].AttributeType,NTFSATTRIBTYPE_INDEXROOT
	je		FoundIndexRoot
	cmp		[esi][eax].AttributeType,NTFSATTRIBTYPE_INDEXALLOC
	je		FoundIndexAlloc
MoveToNextAttribute:
	add		eax,[esi][eax].ThisLength
	jmp		NextAttribute

FoundIndexAlloc:
	lea		edx,[esi][eax]
	mov		pIndexAlloc,edx
	cmp		pIndexRoot,0
	je		MoveToNextAttribute
	jmp		SearchTree

FoundIndexRoot:
ASSUME EAX:PTR NTFSATTRIBHEADER_RES
;	GfxOutputVar	"Relative Attrib Addr: ",eax
	movzx	ecx,[esi][eax].AttributeOffset
	add		ecx,eax
ASSUME ECX:PTR NTFSINDEXROOTATTRIB
;	GfxOutputVar	"Indexing Attrib: ",[esi][ecx].IndexingAttributeType
;	GfxOutputVar	"Collation Rule: ",[esi][ecx].CollationRule
;	GfxOutputVar	"Bytes/Node in Allocation: ",[esi][ecx].BytesPerIndexNode
;	GfxOutputVar	"Clus/Node in Allocation: ",dword ptr [esi][ecx].ClustersPerIndexNode
	add		ecx,sizeof NTFSINDEXROOTATTRIB
ASSUME ECX:PTR NTFSINDEXHEADER
;	GfxOutputVar	"OffFirstIndexEntry: ",[esi][ecx].OffFirstIndexEntry
	test	[esi][ecx].Flags,NTFSINDEXFLAG_LARGE
	pushf
	add		ecx,[esi][ecx].OffFirstIndexEntry
;	GfxOutputVar	"Index Entry Addr: ",ecx
	mov		pIndexRoot,ecx
	add		pIndexRoot,esi
	popf
	jz		SearchTree			;no $INDEX_ALLOCATION for this directory
	cmp		pIndexAlloc,0
	je		MoveToNextAttribute
	
SearchTree:
	mov		ecx,pIndexRoot
ASSUME ECX:PTR NTFSINDEXENTRY
NextEntry:
;IF GFX_TESTING_MODE
;	GfxOutputVar	"FileRef:",dword ptr [ecx].FILERef
;	GfxOutputVar	"        ",dword ptr [ecx].FILERef[4]
;	GfxOutputVar	"Lengths:",dword ptr [ecx].ThisLength
;	GfxOutputVar	"Flags:",dword ptr [ecx].Flags
;;	GfxOutputVar	"Next Dword:",dword ptr [ecx].Flags[4]
;;	GfxOutputVar	"Next Dword:",dword ptr [ecx].Flags[8]
;;	GfxOutputVar	"Next Dword:",dword ptr [ecx].Flags[12]
;;	GfxOutputVar	"Next Dword:",dword ptr [ecx].Flags[16]
;;	GfxOutputVar	"Next Dword:",dword ptr [ecx].Flags[20]
;;	GfxOutputVar	"Next Dword:",dword ptr [ecx].Flags[24]
;;	GfxOutputVar	"Next Dword:",dword ptr [ecx].Flags[28]
;;	GfxOutputVar	"Next Dword:",dword ptr [ecx].Flags[32]
;ENDIF
	test	[ecx].Flags,NTFSINDEXENTRYFLAG_LAST
	jnz		CheckSubnode
;	GfxOutputVar	"FileName:",dword ptr [ecx][sizeof NTFSINDEXENTRY][sizeof NTFSFILENAMEATTRIB]
;	GfxOutputVar	"         ",dword ptr [ecx][sizeof NTFSINDEXENTRY][sizeof NTFSFILENAMEATTRIB][4]
;	GfxOutputVar	"         ",dword ptr [ecx][sizeof NTFSINDEXENTRY][sizeof NTFSFILENAMEATTRIB][8]
;	GfxOutputVar	"         ",dword ptr [ecx][sizeof NTFSINDEXENTRY][sizeof NTFSFILENAMEATTRIB][12]
;	push	ecx
	lea		edi,[ecx][sizeof NTFSINDEXENTRY][sizeof NTFSFILENAMEATTRIB]		;offset of the filename part of the $FILE_NAME key (and note that the key does not contain the attribute header)
ASSUME ECX:PTR NTFSFILENAMEATTRIB
	movzx	ebx,[ecx][sizeof NTFSINDEXENTRY].FilenameLength	;length in characters of the Unicode filename
ASSUME ECX:PTR NTFSINDEXENTRY
;	GfxOutputVar	"Filename with length: ",ebx
	mov		esi,pName
	test	ebx,ebx
	jz		CheckFilenameEnd
NextFilenameLetter:
;### SEE - TODO31: ###
	lodsw
	cmp		ax,"a"
	jb		NotLowercaseSource
	cmp		ax,"z"
	ja		NotLowercaseSource
	and		al,not 20h
NotLowercaseSource:
	mov		dx,[edi]
	add		edi,2
	cmp		dx,"a"
	jb		NotLowercaseDest
	cmp		dx,"z"
	ja		NotLowercaseDest
	and		dl,not 20h
NotLowercaseDest:
	cmp		dx,ax
;IF GFX_TESTING_MODE
;	pushfd
;	pop		eax
;	pushf
;	GfxOutputVar	"CPU Flags are: ",eax
;	popf
;ENDIF
	ja		CheckSubnode
	jne		NotThisEntry
	dec		ebx
	jnz		NextFilenameLetter
;	cmp		eax,eax	;make sure zero flag set and carry flag set, in case name length of 0 is allowed at some point
;	stc				;forcing check to see if parameter filename starts with terminator
;	repe	cmpsw										;Unicode, compare by word
;	pop		ecx
;	ja		CheckSubnode								;check subnode if key filename greater than parameter filename
;	jne		NotThisEntry
CheckFilenameEnd:
	cmp		word ptr [esi],0							;check that key and parameter have same length before can say whether equal
	je		Found
NotThisEntry:
;	GfxOutput	"Search next entry in this node"
	xor		edi,edi										;otherwise move to next entry in this node
	mov		di,[ecx].ThisLength
	add		ecx,edi
	jmp		NextEntry

Found:
;	GfxOutput "File found"
	mov		eax,dword ptr [ecx].FILERef
	mov		edx,dword ptr [ecx].FILERef[4]
;	GfxOutputVar "File ref: ",eax
;	GfxOutputVar "          ",edx
	pop		ebx
	pop		edi
	pop		esi
	ret

CheckSubnode:
	test	[ecx].Flags,NTFSINDEXENTRYFLAG_SUBNODE
	jz		NotFound
;	GfxOutput "Search subnode"
	xor		edi,edi
	mov		di,[ecx].ThisLength
;	GfxOutputVar "Length of prev Attribute",edi
	add		ecx,edi
;	GfxOutputVar "Offset of next Attribute",ecx
	mov		eax,dword ptr [ecx][-8]
	mov		edx,dword ptr [ecx][-4]
	and		edx,0FFFFh									;Note: the VCN listed here also contains an Update Sequence Number in the top word, so remove it
;	GfxOutputVar "VCN:",eax
;	GfxOutputVar "    ",edx
	invoke	VirtualClusNumToSector,pPartition,eax,edx,pIndexAlloc
;	GfxOutputVar "Sector:",edx
;	GfxOutputVar "       ",ecx
	mov		edi,pPartition
ASSUME EDI:PTR PARTITIONINFO_NTFS
	movsx	ebx,[edi].ClusPerINDXBuf
	test	ebx,ebx
	js		IndexAllocLessThan1Cluster
	cmp		eax,ebx
	jb		RunBoundaryInIndexNode

	movzx	eax,[edi].SectorsPerClus
	push	edx
	mul		ebx
	pop		edx
	mov		ebx,[edi].Header.DeviceNum
	sub		ebx,DEVICENUM_ATA0
	invoke	ATAReadSectors,pIndexScratch,ebx,edx,ecx,eax
	mov		ecx,pIndexScratch
ASSUME ECX:PTR NTFSINDEXALLOCHEADER
	add		ecx,[ecx].OffFirstIndexEntry
	add		ecx,offset NTFSINDEXALLOCHEADER.OffFirstIndexEntry
	jmp		NextEntry


RunBoundaryInIndexNode:
;	GfxOutput	"No support yet for run boundaries in $INDEX_ALLOCATION nodes"
;	jmp		NotFound
IndexAllocLessThan1Cluster:
;	GfxOutput	"No support yet for $INDEX_ALLOCATION nodes < 1 cluster"
ASSUME EDI:NOTHING
ASSUME ECX:NOTHING
ASSUME EAX:NOTHING
ASSUME ESI:NOTHING
NotFound:
;	GfxOutput "File not found"
	xor		eax,eax
	xor		edx,edx
	pop		ebx
	pop		edi
	pop		esi
	ret
SearchNTFSDirectory		endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: GetNTFSFileRecord																								*
;*																																*
;*	This procedure reads in the NTFS file record of the file with the specified file record number.								*
;*																																*
;*	Parameters:																													*
;*		pDest			- address to which the file record is to be written														*
;*		pPartition		- address of <PARTITIONINFO_NTFS> structure for the NTFS partition										*
;*		FileRecNumLow	- low dword of file record number																		*
;*		FileRecNumHigh	- high dword of file record number																		*
;*																																*
;*	Local Variables:																											*
;*		nClusLeft		- number of clusters left (if file record is 1 cluster or larger)										*
;*																																*
;<*******************************************************************************************************************************
GetNTFSFileRecord		proc	pDest:DWORD,pPartition:PTR PARTITIONINFO_NTFS,FileRecNumLow:DWORD,FileRecNumHigh:DWORD
 LOCAL nClusLeft:DWORD
	pusha
	mov		edi,pPartition
ASSUME EDI:PTR PARTITIONINFO_NTFS
	mov		esi,[edi].pMFTFileRecord
ASSUME ESI:PTR NTFSFILEHEADER
	xor		ebx,ebx
	mov		bx,[esi].OffAttributes
	add		esi,ebx
ASSUME ESI:PTR NTFSATTRIBHEADER
NextAttribute:
;	GfxOutputVar	"MFT Attrib type: ",[esi].AttributeType
	cmp		[esi].AttributeType,NTFSATTRIBTYPE_END_MARKER
	je		Error
	cmp		[esi].AttributeType,NTFSATTRIBTYPE_DATA
	je		FoundMFTData
	add		esi,[esi].ThisLength
	jmp		NextAttribute
FoundMFTData:
	
	xor		eax,eax
	mov		al,[edi].ClusPerFILERec
	test	al,al
	js		BytePowerLength
	
	mov		nClusLeft,eax
	mov		ecx,eax
	mul		FileRecNumLow
	xchg	eax,ecx
	mov		ebx,edx
	mul		FileRecNumHigh
	add		ebx,eax
NextClusters:
;	GfxOutputVar "MFT VCN: ",ecx
;	GfxOutputVar "         ",ebx
	push	ecx			;low dword of cluster num
	invoke	VirtualClusNumToSector,edi,ecx,ebx,esi
;	GfxOutputVar "Sector #: ",edx
;	GfxOutputVar "          ",ecx
	cmp		eax,nClusLeft
	jae		EnoughConsecutiveClusters
	sub		nClusLeft,eax
	add		[esp],eax	;low dword of cluster num
	adc		ebx,0
	push	edx
	xor		edx,edx
	mov		dl,[edi].SectorsPerClus
	mul		edx
	pop		edx
	push	ebx
	mov		ebx,[edi].Header.DeviceNum
	sub		ebx,DEVICENUM_ATA0
	invoke	ATAReadSectors,pDest,ebx,edx,ecx,eax
	pop		ebx
	pop		ecx
	jmp		NextClusters
	
EnoughConsecutiveClusters:
	mov		eax,nClusLeft
	push	edx
	xor		edx,edx
	mov		dl,[edi].SectorsPerClus
	mul		edx
	pop		edx
	mov		ebx,[edi].Header.DeviceNum
	sub		ebx,DEVICENUM_ATA0
	invoke	ATAReadSectors,pDest,ebx,edx,ecx,eax
	popa
	ret
	
BytePowerLength:
	neg		al
IF ATA_SECTOR_SIZE NE 200h
	.err	<Change line in GetNTFSFileRecord now that ATA_SECTOR_SIZE is not 200h>
ENDIF
	sub		al,9	;ATA_SECTOR_SIZE is 2^9
	mov		cl,al
	mov		al,1
	shl		eax,cl
	push	eax
	mov		eax,FileRecNumLow
	mov		edx,FileRecNumHigh
	shld	edx,eax,cl
	shl		eax,cl
	movzx	ecx,[edi].SectorsPerClus
	push	eax		;take into account chance of VCN>=2^32
	mov		eax,edx	;so need to avoid divide overflow
	xor		edx,edx	;
	div		ecx		;
	mov		ebx,eax	;ebx has upper dword of VCN
	pop		eax		;edx:eax has sector # mod (SecPerClus*2^32)
	div		ecx
	push	edx		;edx has # of sectors to add after finding sector of the cluster
;	GfxOutputVar "MFT VCN: ",ecx
;	GfxOutputVar "         ",ebx
	invoke	VirtualClusNumToSector,edi,eax,ebx,esi
	pop		eax
	add		edx,eax
	adc		ecx,0
;	GfxOutputVar "Sector #: ",edx
;	GfxOutputVar "          ",ecx
	pop		eax
	mov		ebx,[edi].Header.DeviceNum
	sub		ebx,DEVICENUM_ATA0
;	GfxOutputVar	"# of Sectors Read in GetNTFSFileRecord:",eax
	invoke	ATAReadSectors,pDest,ebx,edx,ecx,eax
Error:
	popa
	ret
ASSUME EDI:NOTHING,ESI:NOTHING
GetNTFSFileRecord		endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: ReadVirtualClusters																								*
;*																																*
;*	This procedure reads the specified range of virtual cluster of any non-resident attribute.									*
;*																																*
;*	Parameters:																													*
;*		pPartition		- address of <PARTITIONINFO_NTFS> structure for the NTFS partition										*
;*		VCNLow			- low dword of virtual cluster number																	*
;*		VCNHigh			- high dword of virtual cluster number																	*
;*		pAttribute		- address of the <NTFSATTRIBHEADER_NRES> structure for the attribute									*
;*		pDestination	- address to which the data is to be read																*
;*		nClusters		- number of clusters to read																			*
;*																																*
;<*******************************************************************************************************************************
ReadVirtualClusters		proc	pPartition:PTR PARTITIONINFO_NTFS,VCNLow:DWORD,VCNHigh:DWORD,pAttribute:DWORD,pDestination:DWORD,nClusters:DWORD
	push	ebx
	push	esi
	push	edi
	mov		esi,pPartition
ASSUME ESI:PTR PARTITIONINFO_NTFS
NextClusterRun:
	invoke	VirtualClusNumToSector,esi,VCNLow,VCNHigh,pAttribute
	cmp		eax,nClusters
	cmova	eax,nClusters
	sub		nClusters,eax
	add		VCNLow,eax
	adc		VCNHigh,0
	
	mov		ebx,edx
	xor		edx,edx
	mov		dl,[esi].SectorsPerClus
	mul		edx
	test	ebx,ebx
	jnz		NotSparse
	test	ecx,ecx
	jz		Sparse
NotSparse:
	mov		edx,[esi].Header.DeviceNum
	sub		edx,DEVICENUM_ATA0
	push	eax
	invoke	ATAReadSectors,pDestination,edx,ebx,ecx,eax
	pop		eax
IF ATA_SECTOR_SIZE NE 200h
	.err	<Change line in ReadVirtualClusters now that ATA_SECTOR_SIZE is not 200h>
ENDIF
	shl		eax,9	;ATA_SECTOR_SIZE is 2^9
	add		pDestination,eax
	jmp		DoneClusterRun
Sparse:
IF ATA_SECTOR_SIZE NE 200h
	.err	<Change line in ReadVirtualClusters now that ATA_SECTOR_SIZE is not 200h>
ENDIF
	shl		eax,9-2	;ATA_SECTOR_SIZE is 2^9
	mov		edi,pDestination
	mov		ecx,eax
	xor		eax,eax
	rep stosd
	mov		pDestination,edi
	
DoneClusterRun:
	cmp		nClusters,0
	jnz		NextClusterRun
	pop		edi
	pop		esi
	pop		ebx
	ret
ASSUME ESI:NOTHING
ReadVirtualClusters		endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: VirtualClusNumToSector																							*
;*																																*
;*	This procedure determines the starting sector number of the specified virtual cluster of any non-resident attribute.		*
;*																																*
;*	*FIXME:* Add support for offset larger than 4 bytes (>= 2^31 or < -2^31 clusters)											*
;*	*FIXME:* Add support for run length larger than 4 bytes (>= 2^31 or < -2^31 clusters)										*
;*	*FIXME:* Add support for VCN >= 2^32																						*
;*																																*
;*	Parameters:																													*
;*		pPartition		- address of <PARTITIONINFO_NTFS> structure for the NTFS partition										*
;*		VCNLow			- low dword of virtual cluster number																	*
;*		VCNHigh			- high dword of virtual cluster number																	*
;*		pAttribute		- address of the <NTFSATTRIBHEADER_NRES> structure for the attribute									*
;*																																*
;*	Returns:																													*
;*		ecx:edx	- the sector number (edx is low, ecx is high), or 0 if sparse cluster run, or -1 if past end of runs			*
;*		eax		- the number of subsequent clusters in the run																	*
;*																																*
;<*******************************************************************************************************************************
VirtualClusNumToSector	proc	pPartition:PTR PARTITIONINFO_NTFS,VCNLow:DWORD,VCNHigh:DWORD,pAttribute:DWORD
	push	esi
	push	edi
	push	ebx
	mov		esi,pAttribute
ASSUME ESI:PTR NTFSATTRIBHEADER_NRES
	mov		eax,dword ptr [esi].FirstVCN
	mov		edx,dword ptr [esi].FirstVCN[4]
;	GfxOutputVar	"1stVCN:",eax
;	GfxOutputVar	"       ",edx
	sub		VCNLow,eax
	sbb		VCNHigh,edx
;	GfxOutputVar	"RelVCN:",VCNLow
;	GfxOutputVar	"       ",VCNHigh
	jc		PastEndOfRuns
	movzx	eax,[esi].DataRunsOffset
;	GfxOutputVar	"DataRunsOffset:",eax
	add		esi,eax
ASSUME ESI:NOTHING
	cmp		VCNHigh,0
	jne		Over4GCluster
	xor		ecx,ecx	;ecx will keep track of the VCN
	xor		ebx,ebx	;ebx will keep track of the LCN
NextDataRun:
	lodsb
	mov		ah,al
	and		al,0Fh	;al has length of cluster run length
	shr		ah,4	;ah has length of relative cluster offset
;	GfxOutputVar	"Lengths of Offset & Length:",eax
	cmp		al,2
	je		Length2Byte
	jb		LengthBelow2Byte
LengthAbove2Byte:
	cmp		al,4
	je		Length4Byte
	ja		LengthAbove4Byte
Length3Byte:
	mov		edx,[esi]
	shl		edx,8
	add		esi,3
	sar		edx,8
	jmp		LengthFound
LengthBelow2Byte:
	test	al,al	;end marker is 00h, but only have to check low nibble, because length of 0 bytes is invalid
	jz		PastEndOfRuns
Length1Byte:
	movsx	edx,byte ptr [esi]
	inc		esi
	jmp		LengthFound
Length2Byte:
	movsx	edx,word ptr [esi]
	add		esi,2
	jmp		LengthFound
Length4Byte:
	mov		edx,[esi]
	add		esi,4
LengthFound:

	cmp		ah,2
	je		Offset2Byte
	jb		OffsetBelow2Byte
OffsetAbove2Byte:
	cmp		ah,4
	je		Offset4Byte
	ja		OffsetAbove4Byte
Offset3Byte:
	mov		edi,[esi]
	shl		edi,8
	add		esi,3
	sar		edi,8
	jmp		OffsetFound
OffsetBelow2Byte:
	test	ah,ah
	jz		NoOffset
Offset1Byte:
	movsx	edi,byte ptr [esi]
	inc		esi
	jmp		OffsetFound
NoOffset:
	xor		edi,edi	;no offset means that the clusters contain only 0s, so have been omitted (a.k.a. sparse clusters)
Offset2Byte:
	movsx	edi,word ptr [esi]
	add		esi,2
	jmp		OffsetFound
Offset4Byte:
	mov		edi,[esi]
	add		esi,4
OffsetFound:
	
;	GfxOutputVar	"Offset:",edi
;	GfxOutputVar	"Length:",edx
;	GfxOutputVar	"Next 4 bytes of data run:",dword ptr [esi]

	add		ebx,edi
	add		ecx,edx
	cmp		ecx,VCNLow
	jbe		NextDataRun

FoundCluster:
	sub		VCNLow,ecx
	add		VCNLow,edx	;VCNLow contains number of clusters from beginning of run to desired cluster
	add		ebx,VCNLow	;ebx contains LCN
	sub		edx,VCNLow	;edx contains number of subsequent clusters in run, in case calling function wants to know how much it can read/write at once
	test	edi,edi
	jz		SparseCluster
	push	edx
;	GfxOutputVar	"LCN:",ebx
	invoke	LogicalClusNumToSector,pPartition,ebx,0
	pop		eax
;	GfxOutputVar	"Number of consecutive clusters: ",eax
	pop		ebx
	pop		edi
	pop		esi
	ret

SparseCluster:
	mov		eax,edx
	xor		ecx,ecx
	xor		edx,edx
	pop		ebx
	pop		edi
	pop		esi
	ret

OffsetAbove4Byte:
;### SEE - TODO30: ###
;	GfxOutput	"No support yet for offset >= 2^31"
;	jmp		PastEndOfRuns
LengthAbove4Byte:
;### SEE - TODO29: ###
;	GfxOutput	"No support yet for cluster run length >= 2^31"
;	jmp		PastEndOfRuns
Over4GCluster:
;### SEE - TODO28: ###
;	GfxOutput	"No support yet for VCN >= 2^32"
PastEndOfRuns:
	xor		ecx,ecx
	dec		ecx
	mov		edx,ecx
	pop		ebx
	pop		edi
	pop		esi
	ret
VirtualClusNumToSector	endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: LogicalClusNumToSector																							*
;*																																*
;*	This procedure determines the starting sector number of the specified logical cluster.										*
;*																																*
;*	Parameters:																													*
;*		pPartition		- address of <PARTITIONINFO_NTFS> structure for the NTFS partition										*
;*		LCNLow			- low dword of logical cluster number																	*
;*		LCNHigh			- high dword of logical cluster number																	*
;*																																*
;*	Returns:																													*
;*		ecx:edx	- the sector number (edx is low, ecx is high)																	*
;*		eax		- the given value of pPartition (this is only returned for convenience of the calling function)					*
;*																																*
;<*******************************************************************************************************************************
LogicalClusNumToSector	proc	pPartition:PTR PARTITIONINFO_NTFS,LCNLow:DWORD,LCNHigh:DWORD
	mov		ecx,pPartition
ASSUME ECX:PTR PARTITIONINFO_NTFS
	mov		eax,LCNLow
	push	ecx
	movzx	ecx,[ecx].SectorsPerClus
ASSUME ECX:NOTHING
	mul		ecx
	push	eax
	push	edx
	mov		eax,LCNHigh
	mul		ecx
	pop		ecx
	pop		edx
	add		ecx,eax
	pop		eax
ASSUME EAX:PTR PARTITIONINFO_NTFS
	add		edx,dword ptr [eax].Header.FirstSector
	adc		ecx,dword ptr [eax].Header.FirstSector[4]
	ret
ASSUME EAX:NOTHING
LogicalClusNumToSector	endp

;>*******************************************************************************************************************************
CoreCode		ends