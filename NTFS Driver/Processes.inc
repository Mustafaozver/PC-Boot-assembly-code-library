.nolist

;********************************************************************************************************************************
;*																																*
;*	File: Processes.inc																											*
;*																																*
;*	This file defines structures and cosntants for process management functions of PwnOS.										*
;*																																*
;*	See Also:																													*
;*		- <Processes.asm>																										*
;*		- <Threads.inc>																											*
;*		- <Threads.asm>																											*
;*		- <Sync>																												*
;*																																*
;*	Authors:																													*
;*		- Neil G. Dickson																										*
;*																																*
;********************************************************************************************************************************

GetCurrentProcess	proto
CreateProcess		proto	pName:DWORD,DataSize:DWORD,pData:DWORD,Flags:DWORD
DestroyProcess		proto	hProcess:DWORD
ExitProcess			proto	returnCode:DWORD


;********************************************************************************************************************************
;*																																*
;*	Structure: PROCESSSTRUCT																									*
;*																																*
;*	This structure defines the state of a process.																				*
;*																																*
;*	Members:																													*
;*		HandleType		- HANDLE_TYPE_PROCESS																					*
;*		PriorityLevel	- priority of the process; see <Process Priorities>														*
;*		pThreadList		- handle of the first thread in the thread list															*
;*		hNextSibling	- handle of the next process in the process list (see <pProcessList>)									*
;*		Flags			- miscellaneous status flags; none are defined at this time												*
;*																																*
;********************************************************************************************************************************
PROCESSSTRUCT		STRUCT
	HandleType		dword	?
	PriorityLevel	dword	?
	pThreadList		dword	?
	hNextSibling	dword	?
	Flags			dword	?
PROCESSSTRUCT		ENDS


;********************************************************************************************************************************
;*																																*
;*	Constants: Process Priorities																								*
;*																																*
;*	These constants define thread priorities for use in <PROCESSSTRUCT>.PriorityLevel.											*
;*																																*
;*	Members:																													*
;*	PROCESS_PRIORITY_IDLE			- process threads are only run when no other threads are queued to run						*
;*	PROCESS_PRIORITY_LOWEST			- lowest non-idle priority																	*
;*	PROCESS_PRIORITY_BELOW_NORMAL	- below-normal, but not lowest, priority													*
;*	PROCESS_PRIORITY_NORMAL			- normal (and default) priority																*
;*	PROCESS_PRIORITY_ABOVE_NORMAL	- above-normal, but not highest, priority													*
;*	PROCESS_PRIORITY_HIGHEST		- highest non-time-critical priority														*
;*	PROCESS_PRIORITY_TIME_CRITICAL	- process threads are likely to be always first in the queue to run whenever they're queued	*
;*	PROCESS_PRIORITY_ERROR_RETURN	- not a process priority; indicates error in functions returning a process priority			*
;*																																*
;********************************************************************************************************************************
PROCESS_PRIORITY_IDLE			equ	-15
PROCESS_PRIORITY_LOWEST			equ	-2
PROCESS_PRIORITY_BELOW_NORMAL	equ	-1
PROCESS_PRIORITY_NORMAL			equ	0
PROCESS_PRIORITY_ABOVE_NORMAL	equ	1
PROCESS_PRIORITY_HIGHEST		equ	2
PROCESS_PRIORITY_TIME_CRITICAL	equ	15
PROCESS_PRIORITY_ERROR_RETURN	equ	7FFFFFFFh



;********************************************************************************************************************************
;*																																*
;*	Constants: Process Creation Flags																							*
;*																																*
;*	These constants define flags for the Flags parameter of <CreateProcess>.													*
;*																																*
;*	Members:																													*
;*	CREATE_PROCESS_FLAG_SYSTEM		- create a system process (in privilege level 0)											*
;*																																*
;********************************************************************************************************************************
CREATE_PROCESS_FLAG_SYSTEM		equ	1

.list