package libgopeed

// #cgo LDFLAGS: -static-libstdc++
import "C"
import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/GopeedLab/gopeed/pkg/rest"
	"github.com/GopeedLab/gopeed/pkg/rest/model"

	"github.com/ipfs/boxo/files"
	ipfspath "github.com/ipfs/boxo/path"
	"github.com/ipfs/kubo/core/coreapi"
	coreiface "github.com/ipfs/kubo/core/coreiface" // <--- 导入 coreiface
	"github.com/ipfs/kubo/core/coreiface/options"
	ipfs "github.com/marssuren/gomobile_ipfs_0/go/bind/core"
	// 需要导入 ipld 包
	// 需要导入 ipld 包
)

// 全局变量，保存IPFS节点和上下文
var (
	ipfsNode    *ipfs.IpfsMobile
	ipfsContext context.Context
	ipfsCancel  context.CancelFunc
	// 用于存储下载进度的并发安全 Map
	// key: string (downloadID), value: *DownloadProgress
	downloadProgressMap sync.Map
)

// DirectoryEntry 表示 IPFS 目录中的一个条目
type DirectoryEntry struct {
	Name string `json:"name"` // 条目名称
	Cid  string `json:"cid"`  // 条目自身的 CID
	Type string `json:"type"` // 条目类型 ("file" or "directory")
	Size int64  `json:"size"` // 条目大小 (文件大小)
}

// DownloadProgress 存储单个文件下载的进度信息
type DownloadProgress struct {
	DownloadID     string    `json:"downloadID"` // 唯一标识符
	FilePath       string    `json:"filePath"`   // 本地保存路径
	TotalBytes     int64     `json:"totalBytes"`
	BytesRetrieved int64     `json:"bytesRetrieved"`
	StartTime      time.Time `json:"startTime"`
	IsCompleted    bool      `json:"isCompleted"`
	ErrorMessage   string    `json:"errorMessage"` // 用于记录错误
	HasError       bool      `json:"hasError"`     // <--- 添加 HasError 字段
}

// ProgressInfo 用于从 Go 传递进度信息给 Dart
type ProgressInfo struct {
	TotalBytes     int64   `json:"totalBytes"`
	BytesRetrieved int64   `json:"bytesRetrieved"`
	SpeedBps       float64 `json:"speedBps"` // Bytes per second
	ElapsedTimeSec float64 `json:"elapsedTimeSec"`
	IsCompleted    bool    `json:"isCompleted"`
	HasError       bool    `json:"hasError"`
	ErrorMessage   string  `json:"errorMessage"`
}

// progressWriter 实现了 io.Writer，用于在写入本地文件的同时更新进度
type progressWriter struct {
	progressID string
	written    int64 // 原子更新或使用互斥锁保证并发安全（io.Copy 在单个 goroutine 中调用，暂时不用锁）
}

// --- 为 progressWriter 添加 Write 方法以实现 io.Writer ---
func (pw *progressWriter) Write(p []byte) (n int, err error) {
	n = len(p) // 假设写入总是成功，实际写入由 MultiWriter 的其他 Writer (outFile) 处理
	pw.written += int64(n)

	// 更新全局进度 Map
	val, ok := downloadProgressMap.Load(pw.progressID)
	if ok {
		progress := val.(*DownloadProgress)
		progress.BytesRetrieved = pw.written // 更新已下载字节
		// 注意：这里只更新 BytesRetrieved，速率等在 Query 时计算
		downloadProgressMap.Store(pw.progressID, progress) // 存回更新后的对象
	}
	// 返回 len(p) 和 nil 错误，表明这部分（进度跟踪）逻辑成功
	return n, nil
}

//
// Gopeed 下载功能
//

func Start(cfg string) (int, error) {
	var config model.StartConfig
	if err := json.Unmarshal([]byte(cfg), &config); err != nil {
		return 0, err
	}
	config.ProductionMode = true
	return rest.Start(&config)
}

func Stop() {
	rest.Stop()
}

//
// IPFS 功能
//

// InitIPFS 初始化IPFS仓库
func InitIPFS(repoPath string) (bool, error) {
	// 检查仓库是否已初始化
	_, err := ipfs.OpenRepo(repoPath)

	if err == nil {
		// 仓库已存在
		return true, nil
	}

	// 创建默认配置
	cfg, err := ipfs.NewDefaultConfig()
	if err != nil {
		return false, err
	}

	// 初始化仓库
	if err := ipfs.InitRepo(repoPath, cfg); err != nil {
		return false, err
	}

	return true, nil
}

// StartIPFS 启动IPFS节点
func StartIPFS(repoPath string) (string, error) {
	// 创建上下文
	ipfsContext, ipfsCancel = context.WithCancel(context.Background())

	// 打开仓库
	repo, err := ipfs.OpenRepo(repoPath)
	if err != nil {
		return "", err
	}

	// 创建IPFS节点配置
	ipfsConfig := &ipfs.IpfsConfig{
		RepoMobile: repo.Mobile(),
		ExtraOpts: map[string]bool{
			"pubsub": true,
			"ipnsps": true,
		},
	}

	// 创建并启动IPFS节点
	ipfsNode, err = ipfs.NewNode(ipfsContext, ipfsConfig)
	if err != nil {
		ipfsCancel()
		return "", err
	}

	// 返回节点ID
	return ipfsNode.PeerHost().ID().String(), nil
}

// StopIPFS 停止IPFS节点
func StopIPFS() error {
	if ipfsNode != nil {
		err := ipfsNode.IpfsNode.Close()
		ipfsNode = nil
		if ipfsCancel != nil {
			ipfsCancel()
			ipfsCancel = nil
		}
		return err
	}
	return nil
}

// AddFileToIPFS 添加文件内容到IPFS
func AddFileToIPFS(content string) (string, error) {
	if ipfsNode == nil {
		return "", nil
	}

	// 获取API
	api, err := coreapi.NewCoreAPI(ipfsNode.IpfsNode)
	if err != nil {
		return "", err
	}

	// 创建一个内存中的文件
	r := strings.NewReader(content)
	fileNode := files.NewReaderFile(r)

	// 添加到IPFS
	path, err := api.Unixfs().Add(ipfsContext, fileNode, options.Unixfs.Pin(true))
	if err != nil {
		return "", err
	}

	return path.String(), nil
}

// AddFileToIPFS 添加文件内容到IPFS
func AddFileToIPFS2(content string) (string, error) {
	if ipfsNode == nil {
		return "", nil
	}

	// 获取API
	api, err := coreapi.NewCoreAPI(ipfsNode.IpfsNode)
	if err != nil {
		return "", err
	}

	// 创建一个内存中的文件
	r := strings.NewReader(content)
	fileNode := files.NewReaderFile(r)

	// 添加到IPFS
	path, err := api.Unixfs().Add(ipfsContext, fileNode, options.Unixfs.Pin(true))
	if err != nil {
		return "", err
	}

	return path.String(), nil
}

// GetFileFromIPFS 从IPFS获取文件内容 (返回 []byte)
func GetFileFromIPFS(cid string) ([]byte, error) { // <--- 返回类型修改为 []byte
	if ipfsNode == nil {
		return nil, fmt.Errorf("IPFS node is not running")
	}

	api, err := coreapi.NewCoreAPI(ipfsNode.IpfsNode)
	if err != nil {
		return nil, fmt.Errorf("failed to get CoreAPI: %w", err)
	}

	p, err := ipfspath.NewPath("/ipfs/" + cid)
	if err != nil {
		return nil, fmt.Errorf("failed to create IPFS path: %w", err)
	}

	resolvedPath, _, err := api.ResolvePath(ipfsContext, p)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve IPFS path %s: %w", p, err)
	}

	node, err := api.Unixfs().Get(ipfsContext, resolvedPath)
	if err != nil {
		return nil, fmt.Errorf("failed to get node for path %s: %w", resolvedPath, err)
	}

	// --- 类型断言为文件 ---
	f, ok := node.(files.File)
	if !ok {
		// 如果不是文件类型，返回错误
		return nil, fmt.Errorf("node for path %s is not a file", resolvedPath)
	}
	defer f.Close()

	// --- 读取所有字节 (注意大文件问题) ---
	contentBytes, err := io.ReadAll(f)
	if err != nil {
		return nil, fmt.Errorf("failed to read file content from path %s: %w", resolvedPath, err)
	}

	// --- 直接返回字节切片 ---
	return contentBytes, nil // <--- 直接返回 []byte
}

// ListDirectoryFromIPFS 列出指定 CID 对应的目录内容，返回 JSON 字符串
func ListDirectoryFromIPFS(cid string) (string, error) { // <--- 返回类型改为 string
	if ipfsNode == nil {
		return "", fmt.Errorf("IPFS node is not running")
	}

	api, err := coreapi.NewCoreAPI(ipfsNode.IpfsNode)
	if err != nil {
		return "", fmt.Errorf("failed to get CoreAPI: %w", err)
	}

	p, err := ipfspath.NewPath("/ipfs/" + cid)
	if err != nil {
		return "", fmt.Errorf("failed to create IPFS path: %w", err)
	}

	resolvedPath, _, err := api.ResolvePath(ipfsContext, p)
	if err != nil {
		return "", fmt.Errorf("failed to resolve IPFS path %s: %w", p, err)
	}

	entries := make([]DirectoryEntry, 0)
	for item, err := range coreiface.LsIter(ipfsContext, api.Unixfs(), resolvedPath) {
		if err != nil {
			return "", fmt.Errorf("error listing directory %s: %w", resolvedPath, err)
		}

		entryType := "unknown"
		switch item.Type {
		case coreiface.TFile:
			entryType = "file"
		case coreiface.TDirectory:
			entryType = "directory"
		}

		entries = append(entries, DirectoryEntry{
			Name: item.Name,
			Cid:  item.Cid.String(),
			Type: entryType,
			Size: int64(item.Size),
		})
	}

	// 将结果序列化为 JSON 字符串
	jsonData, err := json.Marshal(entries)
	if err != nil {
		return "", fmt.Errorf("failed to marshal directory entries to JSON: %w", err)
	}

	return string(jsonData), nil // <--- 返回 JSON 字符串
}

// DownloadAndSaveFile: 流式下载单个文件到本地，并记录进度
// downloadID 是 Flutter 端生成的唯一 ID，用于后续查询进度
func DownloadAndSaveFile(cid string, localFilePath string, downloadID string) error {
	if ipfsNode == nil {
		return fmt.Errorf("IPFS node is not running")
	}
	api, err := coreapi.NewCoreAPI(ipfsNode.IpfsNode)
	if err != nil {
		return fmt.Errorf("failed to get CoreAPI: %w", err)
	}

	// --- 确保 downloadID 唯一性 (如果需要，可以先检查 Map) ---
	_, loaded := downloadProgressMap.LoadOrStore(downloadID, &DownloadProgress{
		DownloadID:     downloadID,
		FilePath:       localFilePath,
		TotalBytes:     -1, // 初始未知
		BytesRetrieved: 0,
		StartTime:      time.Now(),
		IsCompleted:    false,
		ErrorMessage:   "",
	})
	if loaded {
		// 如果 ID 已存在且未完成，可能需要处理恢复逻辑或报错
		// 简单起见，先假设不会重复使用未完成的 ID
		// 或者，可以先删除旧的再存入新的
		// downloadProgressMap.Delete(downloadID)
		// downloadProgressMap.Store(...)
		fmt.Printf("Warning: Download ID %s already exists. Overwriting progress.\n", downloadID)
		// 重新存储以确保 StartTime 是最新的
		downloadProgressMap.Store(downloadID, &DownloadProgress{
			DownloadID:     downloadID,
			FilePath:       localFilePath,
			TotalBytes:     -1,
			BytesRetrieved: 0,
			StartTime:      time.Now(),
			IsCompleted:    false,
			ErrorMessage:   "",
		})
	}

	// 获取初始进度对象，以便后续更新 TotalBytes
	initialProgressVal, _ := downloadProgressMap.Load(downloadID)
	initialProgress := initialProgressVal.(*DownloadProgress)

	// --- 获取 IPFS 文件节点 ---
	p, err := ipfspath.NewPath("/ipfs/" + cid)
	if err != nil {
		initialProgress.ErrorMessage = fmt.Sprintf("failed to create IPFS path: %s", err)
		initialProgress.HasError = true
		downloadProgressMap.Store(downloadID, initialProgress)
		return err // 直接返回，不用清理文件，因为还没创建
	}

	// 使用 ResolvePath 获取不可变路径
	resolvedPath, _, err := api.ResolvePath(ipfsContext, p)
	if err != nil {
		initialProgress.ErrorMessage = fmt.Sprintf("failed to resolve IPFS path %s: %s", p, err)
		initialProgress.HasError = true
		downloadProgressMap.Store(downloadID, initialProgress)
		return err
	}

	node, err := api.Unixfs().Get(ipfsContext, resolvedPath)
	if err != nil {
		initialProgress.ErrorMessage = fmt.Sprintf("failed to get node for path %s: %s", resolvedPath, err)
		initialProgress.HasError = true
		downloadProgressMap.Store(downloadID, initialProgress)
		return err
	}

	f, ok := node.(files.File)
	if !ok {
		err = fmt.Errorf("node for path %s is not a file", resolvedPath)
		initialProgress.ErrorMessage = err.Error()
		initialProgress.HasError = true
		downloadProgressMap.Store(downloadID, initialProgress)
		return err
	}
	defer f.Close()

	// --- 获取文件总大小并更新进度 ---
	totalSize, err := f.Size()
	if err != nil {
		// 大小未知，依然尝试下载，但在进度报告中体现
		initialProgress.TotalBytes = -1 // 标记大小未知
		fmt.Printf("Warning: failed to get size for file %s: %v. Proceeding without total size.\n", cid, err)
	} else {
		initialProgress.TotalBytes = totalSize
	}
	downloadProgressMap.Store(downloadID, initialProgress) // 存回带有 TotalBytes 的进度

	// --- 创建本地文件和目录 ---
	dirPath := filepath.Dir(localFilePath)
	if err := os.MkdirAll(dirPath, os.ModePerm); err != nil {
		initialProgress.ErrorMessage = fmt.Sprintf("failed to create directory %s: %s", dirPath, err)
		initialProgress.HasError = true
		downloadProgressMap.Store(downloadID, initialProgress)
		return err
	}
	outFile, err := os.Create(localFilePath)
	if err != nil {
		initialProgress.ErrorMessage = fmt.Sprintf("failed to create local file %s: %s", localFilePath, err)
		initialProgress.HasError = true
		downloadProgressMap.Store(downloadID, initialProgress)
		return err
	}
	defer outFile.Close()

	// --- 创建进度写入器 ---
	progWriter := &progressWriter{
		progressID: downloadID,
		written:    0, // written 会在 Write 方法中累加
	}

	// --- 使用 io.Copy 进行流式复制 ---
	multiWriter := io.MultiWriter(outFile, progWriter) // 同时写入文件和更新进度
	_, err = io.Copy(multiWriter, f)
	if err != nil {
		outFile.Close()          // 确保文件关闭以便删除
		os.Remove(localFilePath) // 出错时删除不完整文件
		// 更新进度为错误状态
		finalProgressVal, ok := downloadProgressMap.Load(downloadID)
		if ok {
			finalProgress := finalProgressVal.(*DownloadProgress)
			finalProgress.ErrorMessage = fmt.Sprintf("failed to copy content: %s", err)
			finalProgress.HasError = true
			downloadProgressMap.Store(downloadID, finalProgress)
		}
		return fmt.Errorf("failed to copy content to local file %s: %w", localFilePath, err)
	}

	// --- 下载完成，更新最终状态 ---
	finalProgressVal, ok := downloadProgressMap.Load(downloadID)
	if ok {
		finalProgress := finalProgressVal.(*DownloadProgress)
		finalProgress.IsCompleted = true
		// 确保最终字节数正确，特别是如果 totalSize 未知
		finalProgress.BytesRetrieved = progWriter.written
		if finalProgress.TotalBytes == -1 { // 如果之前大小未知，现在更新为实际写入大小
			finalProgress.TotalBytes = progWriter.written
		} else if finalProgress.BytesRetrieved != finalProgress.TotalBytes {
			// 如果已知大小和写入大小不符，可能需要记录警告
			fmt.Printf("Warning: Final byte count mismatch for %s. Expected %d, got %d\n", downloadID, finalProgress.TotalBytes, finalProgress.BytesRetrieved)
			// 纠正为实际写入大小
			finalProgress.TotalBytes = finalProgress.BytesRetrieved
		}
		downloadProgressMap.Store(downloadID, finalProgress)
	}

	fmt.Printf("Successfully downloaded and saved %s to %s\n", cid, localFilePath)
	return nil // 下载并保存成功
}

// QueryDownloadProgress: 查询指定下载任务的进度信息，返回 JSON 字符串
func QueryDownloadProgress(downloadID string) (string, error) { // <--- 返回类型改为 string
	val, ok := downloadProgressMap.Load(downloadID)
	if !ok {
		// 对于 gomobile，返回空字符串和错误可能更清晰
		return "", fmt.Errorf("download ID %s not found or already cleaned up", downloadID)
	}
	progress := val.(*DownloadProgress)

	elapsedTime := time.Since(progress.StartTime)
	elapsedSeconds := elapsedTime.Seconds()
	if elapsedSeconds < 0.01 {
		elapsedSeconds = 0.01
	}

	speedBps := float64(progress.BytesRetrieved) / elapsedSeconds

	info := ProgressInfo{
		TotalBytes:     progress.TotalBytes,
		BytesRetrieved: progress.BytesRetrieved,
		SpeedBps:       speedBps,
		ElapsedTimeSec: elapsedSeconds,
		IsCompleted:    progress.IsCompleted,
		HasError:       progress.ErrorMessage != "", // 直接计算 HasError
		ErrorMessage:   progress.ErrorMessage,
	}

	// 将结果序列化为 JSON 字符串
	jsonData, err := json.Marshal(info)
	if err != nil {
		return "", fmt.Errorf("failed to marshal progress info to JSON: %w", err)
	}

	return string(jsonData), nil // <--- 返回 JSON 字符串
}

// downloadRecursiveHelper: 内部递归辅助函数
// currentRelativeDir: 当前正在处理的目录相对于顶层目录的路径 (例如 "subdir1/subdir2")
// selectedPaths: key 是相对于 topCid 的完整相对路径
func downloadRecursiveHelper(currentCid string, localCurrentPath string, currentRelativeDir string, selectedPaths map[string]bool, downloadIDPrefix string) error {

	// ListDirectoryFromIPFS 现在返回 JSON 字符串
	entriesJson, err := ListDirectoryFromIPFS(currentCid)
	if err != nil {
		// 如果当前 CID 不是目录或列出失败，记录错误并可能停止这个分支
		fmt.Printf("Error listing directory %s (%s): %v\n", currentRelativeDir, currentCid, err)
		return err // 返回错误，让上层决定如何处理
	}

	// --- 反序列化 JSON ---
	var entries []DirectoryEntry
	if err := json.Unmarshal([]byte(entriesJson), &entries); err != nil {
		// 处理 JSON 反序列化错误
		fmt.Printf("Error unmarshaling directory entries for %s: %v\n", currentCid, err)
		return fmt.Errorf("failed to parse directory listing for %s: %w", currentCid, err)
	}
	// --- ---

	// 确保当前本地目录存在
	if err := os.MkdirAll(localCurrentPath, os.ModePerm); err != nil {
		return fmt.Errorf("failed to create directory %s: %w", localCurrentPath, err)
	}

	// 现在迭代反序列化后的 entries
	for _, entry := range entries {
		// --- 构造条目的相对路径和本地路径 ---
		entryRelativePath := filepath.Join(currentRelativeDir, entry.Name) // 使用 filepath.Join 更安全
		localEntryPath := filepath.Join(localCurrentPath, entry.Name)

		// --- 检查是否需要处理这个条目 ---
		isSelected, containsSelectedChildren := checkSelection(entryRelativePath, entry.Type == "directory", selectedPaths)

		if isSelected || containsSelectedChildren {
			switch entry.Type {
			case "file":
				if isSelected { // 只有当文件本身被选中时才下载
					// 生成唯一 ID
					fileID := fmt.Sprintf("%s_%s", downloadIDPrefix, strings.ReplaceAll(entryRelativePath, string(filepath.Separator), "_"))
					// 启动 goroutine 下载文件
					go func(fileCid, filePath, id string) {
						err := DownloadAndSaveFile(fileCid, filePath, id)
						if err != nil {
							fmt.Printf("Error downloading %s: %v\n", filePath, err)
							// 可以在这里更新进度状态为 error
							val, loaded := downloadProgressMap.Load(id)
							if loaded {
								prog := val.(*DownloadProgress)
								prog.HasError = true
								prog.ErrorMessage = err.Error()
								downloadProgressMap.Store(id, prog)
							} else {
								// 如果启动时就失败，可能需要创建一个错误状态的条目
								downloadProgressMap.Store(id, &DownloadProgress{
									DownloadID: id, FilePath: filePath, TotalBytes: -1, BytesRetrieved: -1,
									HasError: true, ErrorMessage: err.Error(),
								})
							}
						}
					}(entry.Cid, localEntryPath, fileID)
				}

			case "directory":
				// 递归调用处理子目录
				// 递归调用总是需要的，因为它可能包含选中的子文件
				err := downloadRecursiveHelper(entry.Cid, localEntryPath, entryRelativePath, selectedPaths, downloadIDPrefix)
				if err != nil {
					// 处理子目录下载的整体错误（例如无法列出子目录）
					fmt.Printf("Error processing subdirectory %s: %v\n", localEntryPath, err)
					// 可以选择继续处理其他条目，或者向上传递错误
					// return err // 如果希望一个子错误导致整个任务失败
				}
			}
		}
	}
	return nil // 当前目录处理完成（或遇到可忽略的错误）
}

// checkSelection: 辅助函数，判断当前条目是否需要处理
// isDirectory: 当前条目是否是目录
// selectedPaths: 用户选择的所有相对路径 (文件或目录)
// 返回值:
//
//	bool: 当前条目本身是否被精确选中
//	bool: selectedPaths 中是否包含当前目录下的子条目 (仅当 isDirectory 为 true 时有意义)
func checkSelection(currentRelativePath string, isDirectory bool, selectedPaths map[string]bool) (isSelected bool, containsSelectedChildren bool) {
	// 1. 检查当前路径是否被精确选中
	if _, ok := selectedPaths[currentRelativePath]; ok {
		isSelected = true
	}

	// 2. 如果是目录，检查是否有子路径被选中
	if isDirectory {
		prefix := currentRelativePath + string(filepath.Separator)
		if currentRelativePath == "." { // 根目录特殊处理
			prefix = ""
		}
		for path := range selectedPaths {
			if strings.HasPrefix(path, prefix) && path != currentRelativePath { // 确保是真正的子路径
				containsSelectedChildren = true
				break
			}
		}
	}

	// 如果目录本身被选中，则认为其下所有内容也需要处理（隐含选中）
	if isSelected && isDirectory {
		containsSelectedChildren = true
	}

	return isSelected, containsSelectedChildren
}

// StartDownloadSelected: 启动下载任务的入口函数 (导出)
func StartDownloadSelected(topCid string, localBasePath string, selectedPaths []string) (string, error) {
	if ipfsNode == nil {
		return "", fmt.Errorf("IPFS node is not running")
	}

	// 检查 localBasePath 是否有效 (例如，是否是绝对路径，是否有权限等)
	// ...

	selectedMap := make(map[string]bool)
	for _, p := range selectedPaths {
		// 规范化路径分隔符，以匹配 filepath.Join 的结果
		cleanPath := filepath.Clean(strings.ReplaceAll(p, "/", string(filepath.Separator)))
		selectedMap[cleanPath] = true
	}

	// 为整个下载任务生成唯一 ID 前缀
	downloadTaskIDPrefix := fmt.Sprintf("task_%d", time.Now().UnixNano())

	// 异步启动递归下载
	go func() {
		fmt.Printf("Starting download task %s for CID %s to %s\n", downloadTaskIDPrefix, topCid, localBasePath)
		err := downloadRecursiveHelper(topCid, localBasePath, ".", selectedMap, downloadTaskIDPrefix) // 初始相对路径为 "."
		if err != nil {
			// 整个任务启动或执行中遇到不可恢复的错误
			fmt.Printf("Download task %s failed: %v\n", downloadTaskIDPrefix, err)
			// 需要一种方式通知 Flutter 任务失败 (例如，通过一个特殊进度条目或事件)
			// 可以在 map 中存一个 "task_..." 的状态
		} else {
			fmt.Printf("Download task %s processing initiated.\n", downloadTaskIDPrefix)
			// 可以在 map 中存一个 "task_..." 的状态标记完成（所有 goroutine 已启动）
		}
	}()

	return downloadTaskIDPrefix, nil // 立即返回任务前缀
}

// GetIPFSPeerID 获取当前IPFS节点的对等点ID
func GetIPFSPeerID() string {
	if ipfsNode == nil {
		return ""
	}
	return ipfsNode.PeerHost().ID().String()
}
