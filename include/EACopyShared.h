// (c) Electronic Arts. All Rights Reserved.

#pragma once
#undef UNICODE
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
// Only define _HAS_EXCEPTIONS if it's not already defined
#ifndef _HAS_EXCEPTIONS
#define _HAS_EXCEPTIONS 0
#endif

#include <functional>
#include <list>
#include <map>
#include <set>
#include <string>
#include <vector>
struct _OVERLAPPED;

namespace eacopy
{
	class HashContext;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Global Constants

enum { CopyContextBufferSize = 8*1024*1024 }; // This is the chunk size used when reading/writing/copying files
enum { MaxPath = 4096 }; // Max path for EACopy
enum { LogBufferSize = 10000 }; // Size of buffer used when printing log messages

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Types

using								u8			= unsigned char;
using								u16			= unsigned short;
#if defined(_WIN32)
using								uint		= unsigned long;
#else
using								uint		= unsigned int;
#endif
using								s64			= long long;
using								u64			= unsigned long long;
using								String		= std::string;
using								WString		= std::wstring;
template<class T> using				List		= std::list<T>;
template<class K, class V> using	Map			= std::map<K, V>;
template<class K, class L> using	Set			= std::set<K, L>;
template<class T> using				Vector		= std::vector<T>;
template<class T> using				Function	= std::function<T>;
using								FileHandle  = void*;
#define								InvalidFileHandle ((FileHandle)-1)
using								FindFileHandle  = void*;
#define								InvalidFindFileHandle ((FindFileHandle)-1)

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ScopeGuard - Will call provided function when exiting scope

class ScopeGuard
{
public:
						ScopeGuard(Function<void()>&& f) : func(std::move(f)) {}
						~ScopeGuard() { func(); }
	void				cancel() { func = []() {}; }
	void				execute() { func(); func = []() {}; }

private:
	Function<void()>	func;
};



///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// CriticalSection

class CriticalSection
{
public:
						CriticalSection();
						~CriticalSection();

	void				enter();
	void				leave();
	template<class Functor> void scoped(const Functor& f) { enter(); f(); leave(); }

private:
	u64					data[5];
};

class ScopedCriticalSection
{
public:
	ScopedCriticalSection(CriticalSection& cs) : m_cs(cs), m_active(true) { cs.enter(); }
	~ScopedCriticalSection() { leave(); }
	void leave() { if (!m_active) return; m_cs.leave(); m_active = false; }
private:
	CriticalSection& m_cs;
	bool m_active;
};

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Thread

class Event
{
public:
						Event();
						~Event();
	void				set();
	void				reset();
	bool				isSet(uint timeOutMs = 0xFFFFFFFF);

private:
	#if !defined(_WIN32)
	CriticalSection		cs;
	#endif

	void*				ev;
};



///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Thread

class Thread
{
public:
						Thread();
						Thread(Function<int()>&& func);
						~Thread();
	void				start(Function<int()>&& func);
	void				wait();
	bool				getExitCode(uint& outExitCode);

private:
	Function<int()>		func;
	void*				handle;
	uint				exitCode;
	bool				joined;
};



///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Hash

struct Hash
{
	u64 first = 0;
	u64 second = 0;

	bool operator==(const Hash& o) const { return first == o.first && second == o.second; }
	bool operator<(const Hash& o) const { return first == o.first ? second < o.second : first < o.first; }
};

inline bool isValid(const Hash& hash) { return hash.first != 0 || hash.second != 0; }


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Misc

u64						getTime();
inline u64				getTimeMs() { return getTime() / 10000; }
inline u64				timeToMs(u64 time) { return time / 10000; }
bool					equalsIgnoreCase(const wchar_t* a, const wchar_t* b);
bool					lessIgnoreCase(const wchar_t* a, const wchar_t* b);
bool					startsWithIgnoreCase(const wchar_t* str, const wchar_t* substr);
WString					getErrorText(uint error);
WString					getErrorText(const wchar_t* resourceName, uint error);
WString					getLastErrorText();
WString					getProcessesUsingResource(const wchar_t* resourceName);
WString					toPretty(u64 bytes, uint alignment = 0);
WString					toHourMinSec(u64 time, uint alignment = 0);
String					toString(const wchar_t* str);
void					itow(int value, wchar_t* dst, uint dstCapacity);
int						stringEquals(const wchar_t* a, const wchar_t* b);
int						stringEquals(const char* a, const char* b);
bool					stringCopy(wchar_t* dest, uint destCapacity, const wchar_t* source);
#define					eacopy_sizeof_array(array) int(sizeof(array)/sizeof(array[0]))
WString					getVersionString(uint major, uint minor, bool isDebug);
template<class T> T		min(T a, T b) { return a < b ? a : b; }
template<class T> T		max(T a, T b) { return a > b ? a : b; }

struct TimerScope
{
	TimerScope(u64& t) : timer(t), start(getTime()) {}
	~TimerScope() { timer += getTime() - start; }
	u64& timer;
	u64 start;
};

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IO

struct FileTime {
    uint dwLowDateTime;
    uint dwHighDateTime;
};

struct FileInfo
{
	FileTime			creationTime = { 0, 0 };
	FileTime			lastWriteTime = { 0, 0 };
	u64					fileSize = 0;
	// TODO: add attributes here? It will require fixes in server, but can copy things like hidden attr.
};

struct CopyContext
{
						CopyContext();
						~CopyContext();
	u8*					buffers[3];
};

struct IOStats
{
	u64					createReadTime = 0;
	u64					readTime = 0;
	u64					closeReadTime = 0;
	uint				createReadCount = 0;
	uint				readCount = 0;
	uint				closeReadCount = 0;

	u64					createWriteTime = 0;
	u64					writeTime = 0;
	u64					closeWriteTime = 0;
	uint				createWriteCount = 0;
	uint				writeCount = 0;
	uint				closeWriteCount = 0;


	u64					createLinkTime = 0;
	u64					deleteFileTime = 0;
	u64					moveFileTime = 0;
	u64					removeDirTime = 0;
	u64					setLastWriteTime = 0;
	u64					findFileTime = 0;
	u64					fileInfoTime = 0;
	u64					createDirTime = 0;
	u64					copyFileTime = 0;
	uint				createLinkCount = 0;
	uint				deleteFileCount = 0;
	uint				moveFileCount = 0;
	uint				removeDirCount = 0;
	uint				setLastWriteTimeCount = 0;
	uint				findFileCount = 0;
	uint				fileInfoCount = 0;
	uint				createDirCount = 0;
	uint				copyFileCount = 0;
};


enum AccessType
{
	AccessType_Read,
	AccessType_Write,
};

struct					NoCaseWStringLess { bool operator()(const WString& a, const WString& b) const { return lessIgnoreCase(a.c_str(), b.c_str()); } };
using					FilesSet = Set<WString, NoCaseWStringLess>;

enum					UseBufferedIO { UseBufferedIO_Auto, UseBufferedIO_Enabled, UseBufferedIO_Disabled };
bool					getUseBufferedIO(UseBufferedIO use, u64 fileSize);

uint					getFileInfo(FileInfo& outInfo, const wchar_t* fullFileName, IOStats& ioStats);
bool					getFileHash(Hash& outHash, const wchar_t* fullFileName, CopyContext& copyContext, IOStats& ioStats, HashContext& hashContext, u64& hashTime);
bool					equals(const FileInfo& a, const FileInfo& b);
bool					ensureDirectory(const wchar_t* directory, uint attributes, IOStats& ioStats, bool replaceIfSymlink = false, bool expectCreationAndParentExists = true, FilesSet* outCreatedDirs = nullptr);
bool					deleteDirectory(const wchar_t* directory, IOStats& ioStats, bool errorOnMissingFile = true);
bool					deleteAllFiles(const wchar_t* directory, IOStats& ioStats, bool errorOnMissingFile = true);
bool					isAbsolutePath(const wchar_t* path);
bool					openFileRead(const wchar_t* fullPath, FileHandle& outFile, IOStats& ioStats, bool useBufferedIO, _OVERLAPPED* overlapped = nullptr, bool isSequentialScan = true, bool sharedRead = true);
bool					openFileWrite(const wchar_t* fullPath, FileHandle& outFilee, IOStats& ioStats, bool useBufferedIO, _OVERLAPPED* overlapped = nullptr, bool hidden = false, bool createAlways = true, bool sharedRead = false);
bool					writeFile(const wchar_t* fullPath, FileHandle& file, const void* data, u64 dataSize, IOStats& ioStats, _OVERLAPPED* overlapped = nullptr);
bool					readFile(const wchar_t* fullPath, FileHandle& file, void* destData, u64 toRead, u64& read, IOStats& ioStats);
bool					setFileLastWriteTime(const wchar_t* fullPath, FileHandle& file, FileTime lastWriteTime, IOStats& ioStats);
bool					setFilePosition(const wchar_t* fullPath, FileHandle& file, u64 position, IOStats& ioStats);
bool					closeFile(const wchar_t* fullPath, FileHandle& file, AccessType accessType, IOStats& ioStats);
bool					createFile(const wchar_t* fullPath, const FileInfo& info, const void* data, IOStats& ioStats, bool useBufferedIO, bool hidden = false);
bool					createFileLink(const wchar_t* fullPath, const FileInfo& info, const wchar_t* sourcePath, bool& outSkip, IOStats& ioStats, bool deleteAndRetry = true);
bool					copyFile(const wchar_t* source, const wchar_t* dest, bool useSystemCopy, bool failIfExists, bool& outExisted, u64& outBytesCopied, IOStats& ioStats, UseBufferedIO useBufferedIO);
bool					copyFile(const wchar_t* source, const FileInfo& sourceInfo, uint sourceAttributes, const wchar_t* dest, bool useSystemCopy, bool failIfExists, bool& outExisted, u64& outBytesCopied, CopyContext& copyContext, IOStats& ioStats, UseBufferedIO useBufferedIO);
bool					deleteFile(const wchar_t* fullPath, IOStats& ioStats, bool errorOnMissingFile = true);
bool					moveFile(const wchar_t* source, const wchar_t* dest, IOStats& ioStats);
bool					setFileWritable(const wchar_t* fullPath, bool writable);
bool					setFileHidden(const wchar_t* fullPath, bool hidden);
void					convertSlashToBackslash(wchar_t* path);
void					convertSlashToBackslash(wchar_t* path, size_t size);
void					convertSlashToBackslash(char* path);
void					convertSlashToBackslash(char* path, size_t size);
WString					getCleanedupPath(wchar_t* path, uint startIndex = 2, bool lastWasSlash = false);
bool					isLocalPath(const wchar_t* path);
const wchar_t*			convertToShortPath(const wchar_t* path, WString& outTempBuffer);
bool					isDotOrDotDot(const wchar_t* str);


struct					FindFileData { u64 data[1024]; };
FindFileHandle			findFirstFile(const wchar_t* searchStr, FindFileData& findFileData, IOStats& ioStats);
bool					findNextFile(FindFileHandle handle, FindFileData& findFileData, IOStats& ioStats);
void					findClose(FindFileHandle handle, IOStats& ioStats);
uint					getFileInfo(FileInfo& outInfo, FindFileData& findFileData);
wchar_t*				getFileName(FindFileData& findFileData);



///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// FileDatabase

struct FileKey
{
	WString name;
	FileTime lastWriteTime;
	u64 fileSize;

	bool operator<(const FileKey& o) const;
};

class FileDatabase
{
public:
	using			FilesHistory = List<FileKey>;
	struct			FileRec { WString name; Hash hash;  FilesHistory::iterator historyIt; };
	using			FilesMap = Map<FileKey, FileRec>;
	using			FilesHashMap = Map<Hash, FileRec*>;
	struct			PrimeDirRec { WString directory; uint rootLen = 0; };
	using			PrimeDirs = List<PrimeDirRec>;

	FileRec			getRecord(const FileKey& key);
	FileRec			getRecord(const Hash& hash);
	uint			getHistorySize();
	bool			findFileForDeltaCopy(WString& outFile, const FileKey& key);

	void			addToFilesHistory(const FileKey& key, const Hash& hash, const WString& fullFileName);
	void			removeFileHistory(const FileKey& key);
	uint			garbageCollect(uint maxHistory);

	bool			primeDirectory(const WString& directory, IOStats& ioStats, bool useRelativePath, bool flush);
	bool			primeUpdate(IOStats& ioStats);
	bool			primeWait(IOStats& ioStats);

	void			readFile(const wchar_t* fullPath, IOStats& ioStats);
	void			writeFile(const wchar_t* fullPath, IOStats& ioStats);

	CriticalSection	m_primeDirsCs;
	PrimeDirs		m_primeDirs;
	uint			m_primeActive = 0;

	FilesMap		m_files;
	FilesHashMap	m_fileHashes;
	FilesHistory	m_filesHistory;
	CriticalSection	m_filesCs;
};



///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Hash

class HashContext
{
public:
	HashContext(u64& time, u64& count);

	bool init();
	~HashContext();

	void* m_handle = nullptr;
	u64& m_time;
	u64& m_count;
};

class HashBuilder
{
public:
	HashBuilder(HashContext& context);
	~HashBuilder();

	bool add(u8* data, u64 size);
	bool getHash(Hash& outHash);

	HashContext& m_context;
	void* m_handle = nullptr;
};

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Logging

void					logErrorf(const wchar_t* fmt, ...);
void					logFlush();
void					logInfo(const wchar_t* str);
void					logInfof(const wchar_t* fmt, ...);
void					logInfoLinef(const wchar_t* fmt, ...);
void					logInfoLinef();
void					logDebugf(const wchar_t* fmt, ...);
void					logDebugLinef(const wchar_t* fmt, ...);
void					logScopeEnter();
void					logScopeLeave();


class Log
{
public:
	void				init(const wchar_t* logFile, bool logDebug, bool cacheRecentErrors);
	void				deinit(const Function<void()>& lastChanceLogging = Function<void()>());
	bool				isDebug() const { return m_logDebug; }
	void				traverseRecentErrors(const Function<bool(const WString&)>& errorFunc);

private:
	struct				LogEntry { WString str; bool linefeed; bool isError; };

	void				writeEntry(bool isDebuggerPresent, const LogEntry& entry);
	uint				processLogQueue(bool isDebuggerPresent);
	uint				logQueueThread();

	WString				m_logFileName;
	bool				m_logDebug = false;
	bool				m_cacheRecentErrors = false;
	CriticalSection		m_logQueueCs;
	List<LogEntry>*		m_logQueue = nullptr;
	List<WString>		m_recentErrors;
	WString				m_logLastText;
	bool				m_logQueueFlush = false;
	Thread*				m_logThread = nullptr;
	FileHandle			m_logFile = InvalidFileHandle;
	bool				m_logThreadActive = false;
	friend void			logInternal(const wchar_t* buffer, bool flush, bool linefeed, bool isError);
	friend void			logScopeEnter();
	friend void			logScopeLeave();
};

class LogContext
{
public:
						LogContext(Log& log);
						~LogContext();

	int					getLastError() const { return m_lastError; }
	void				resetLastError() { m_lastError = 0; }
	void				mute() { m_muted = true; }

	Log&				log;

private:
	LogContext*			m_lastContext;
	int					m_lastError = 0;
	bool				m_muted = false;
	friend void			logErrorf(const wchar_t* fmt, ...);
	friend void			logInternal(const wchar_t* buffer, bool flush, bool linefeed, bool isError);
};

void					populateStatsTime(Vector<WString>& stats, const wchar_t* name, u64 ms, uint count);
void					populateStatsBytes(Vector<WString>& stats, const wchar_t* name, u64 bytes);
void					populateStatsValue(Vector<WString>& stats, const wchar_t* name, float value);
void					populateStatsValue(Vector<WString>& stats, const wchar_t* name, uint value);
void					populateIOStats(Vector<WString>& stats, const IOStats& ioStats);
void					logInfoStats(const Vector<WString>& stats);
void					logDebugStats(const Vector<WString>& stats);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#if defined(NDEBUG)
constexpr bool isDebug = false;
#else
constexpr bool isDebug = true;
#endif

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#if defined(_WIN32)
#else
void Sleep(uint milliseconds);
uint GetLastError();
#define StringCbPrintfW swprintf
#define wcscpy_s(a, b, c) wcscpy(a, c)
#define wcscat_s(a, b, c) wcscat(a, c)
#define vswprintf_s vswprintf
#define MAX_PATH 260
#define _wcsicmp wcscasecmp
#define _wcsnicmp wcsncasecmp
#define FILE_ATTRIBUTE_READONLY             0x00000001
#define FILE_ATTRIBUTE_HIDDEN               0x00000002
#define FILE_ATTRIBUTE_DIRECTORY            0x00000010
#define FILE_ATTRIBUTE_NORMAL               0x00000080
#define FILE_ATTRIBUTE_REPARSE_POINT        0x00000400
#define ERROR_FILE_NOT_FOUND             2L
#define ERROR_PATH_NOT_FOUND             3L
#define ERROR_INVALID_HANDLE             6L
#define ERROR_NO_MORE_FILES              18L
#define ERROR_ALREADY_EXISTS             183L
#define ERROR_SHARING_VIOLATION          32L
#endif

#define EACOPY_NOT_IMPLEMENTED { Sleep(1000); fflush(stdout); assert(false); }

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

} // namespace eacopy
