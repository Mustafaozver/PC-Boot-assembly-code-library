;********************************************************************************************************************************
;*																																*
;*	File: Processes.asm																											*
;*																																*
;*	This file defines process management functions of PwnOS.																	*
;*																																*
;*	See Also:																													*
;*		- <Processes.inc>																										*
;*		- <Threads.inc>																											*
;*		- <Threads.asm>																											*
;*		- <Sync>																												*
;*																																*
;*	Authors:																													*
;*		- Neil G. Dickson																										*
;*																																*
;********************************************************************************************************************************

CoreData	segment	use32

;********************************************************************************************************************************
;*																																*
;*	Variable: pProcessList																										*
;*																																*
;*	This is the main process list, Contains the handle of the first process in the list.										*
;*																																*
;********************************************************************************************************************************
	pProcessList		DWORD	?
	
;********************************************************************************************************************************
;*																																*
;*	Variable: ProcessAccessLock																									*
;*																																*
;*	This is the <LOCKSTRUCT> for locking access to process management data.														*
;*																																*
;********************************************************************************************************************************
	ProcessAccessLock	LOCKSTRUCT	<0,NULL,NULL,NULL>

CoreData	ends

CoreCode	segment	use32

;********************************************************************************************************************************
;*																																*
;*	Procedure: GetCurrentProcess																								*
;*																																*
;*	This procedure returns the current process handle.																			*
;*																																*
;*	Returns:																													*
;*		- current process handle (address of <PROCESSSTRUCT>)																	*
;*																																*
;<*******************************************************************************************************************************
GetCurrentProcess	proc
	xor		eax,eax
	str		ax
IF VA_GDT NE 0
	add		eax,VA_GDT
ENDIF
	mov		ecx,[eax]		;limit0,limit1,base0,base1	
	mov		edx,[eax][4]	;base2,stuff,stuff,base3
	shrd	ecx,edx,8
	shr		edx,24
	shrd	ecx,edx,8		;base0,base1,base2,base3
	lea		eax,[ecx-offset EXTENDEDTSS.GeneralState]
	mov		eax,[eax].THREADSTRUCT.hProcess
	ret
GetCurrentProcess	endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: CreateProcess																									*
;*																																*
;*	This procedure creates a new process.																						*
;*																																*
;*	*Not Implemented*																											*
;*																																*
;*	Parameters:																													*
;*		pName		- address of string holding path of the process to create													*
;*		DataSize	- size of data block to be passed to the process, or 0 if none												*
;*		pData		- address of data block to be passed to the process, or NULL if none										*
;*		Flags		- process creation flags; (see <Process Creation Flags>)													*
;*																																*
;*	Returns:																													*
;*		- handle of the new process (address of <PROCESSSTRUCT>)																*
;*																																*
;<*******************************************************************************************************************************
CreateProcess	proc	pName:DWORD,DataSize:DWORD,pData:DWORD,Flags:DWORD

	pusha
	mov		edi,VA_GFX
	mov		ecx,1024*768
	mov		eax,DataSize
@@:
	stosd
	dec		edi
	dec		ecx
	jnz		@B
	popa



	invoke	OpenFile,pName,FILE_ACCESS_READ,FILE_OPEN_EXISTING,0
	mov		ebx,eax
	invoke	GetFileSize,eax
	mov		esi,eax
	add		eax,0FFFFh
	shr		eax,16
	invoke	AllocatePages,NULL,eax,MEM_COMMIT,PAGE_EXECUTE_READWRITE or PAGE_NOACCESS
	mov		edi,eax
	invoke	ReadFile,ebx,eax,esi
	invoke	CloseFile,ebx
	
	
	
	
	
	
	
	
	ret
CreateProcess	endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: DestroyProcess																									*
;*																																*
;*	This procedure destroys a process.																							*
;*																																*
;*	*Not Implemented*																											*
;*																																*
;*	Parameters:																													*
;*		hProcess	- handle of process to destroy																				*
;*																																*
;<*******************************************************************************************************************************
DestroyProcess	proc	hProcess:DWORD

	ret
DestroyProcess	endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: ExitProcess																										*
;*																																*
;*	This procedure exits the current process, giving the specified return code.													*
;*																																*
;*	*Not Implemented*																											*
;*																																*
;*	Parameters:																													*
;*		returnCode	- return code of the current process																		*
;*																																*
;<*******************************************************************************************************************************
ExitProcess		proc	returnCode:DWORD

	ret
ExitProcess		endp

;>*******************************************************************************************************************************

;********************************************************************************************************************************
;*																																*
;*	Section: Gateway Functions of Processes.asm																					*
;*																																*
;********************************************************************************************************************************

;********************************************************************************************************************************
;*																																*
;*	Procedure: GetCurrentProcessU																								*
;*																																*
;*	Gateway function for <GetCurrentProcess>																					*
;*																																*
;<*******************************************************************************************************************************
GetCurrentProcessU	proc
	invoke	GetCurrentProcess
	ret
GetCurrentProcessU	endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: CreateProcessU																									*
;*																																*
;*	Gateway function for <CreateProcess>																						*
;*																																*
;*	This clears the CREATE_PROCESS_FLAG_SYSTEM flag if it is set, and ensures that none of the data block is in system space.	*
;*																																*
;<*******************************************************************************************************************************
CreateProcessU		proc
	mov		ecx,[esp][12]	;Privilege Level 3 esp, and ss should be the same as ds
	mov		eax,[ecx][4]	;DataSize
	cmp		eax,VA_SYSTEM_MEMORY
	jae		Failure
	add		eax,[ecx][8]
	cmp		eax,VA_SYSTEM_MEMORY
	jae		Failure
	mov		eax,[ecx][12]
	and		eax,not CREATE_PROCESS_FLAG_SYSTEM
	invoke	CreateProcess,dword ptr [ecx][0],dword ptr [ecx][4],dword ptr [ecx][8],eax
	ret
Failure:
	xor		eax,eax
	ret
CreateProcessU		endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: DestroyProcessU																									*
;*																																*
;*	Gateway function for <DestroyProcess>																						*
;*																																*
;*	This ensures that none of the <PROCESSSTRUCT> is in system space.															*
;*																																*
;<*******************************************************************************************************************************
DestroyProcessU		proc
	mov		ecx,[esp][12]	;Privilege Level 3 esp, and ss should be the same as ds
	mov		eax,[ecx][0]	;hProcess
	cmp		eax,VA_SYSTEM_MEMORY
	jae		Failure
	add		eax,sizeof PROCESSSTRUCT
	cmp		eax,VA_SYSTEM_MEMORY
	jae		Failure
	invoke	DestroyProcess,dword ptr [ecx][0]
	ret
Failure:
	ret
DestroyProcessU		endp

;>*******************************************************************************************************************************
;*																																*
;*	Procedure: ExitProcessU																										*
;*																																*
;*	Gateway function for <ExitProcess>																							*
;*																																*
;<*******************************************************************************************************************************
ExitProcessU		proc
	mov		ecx,[esp][12]	;Privilege Level 3 esp, and ss should be the same as ds
	invoke	ExitProcess,dword ptr [ecx][0]
	ret
ExitProcessU		endp

;>*******************************************************************************************************************************

CoreCode	ends