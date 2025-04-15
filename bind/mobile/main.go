package libgopeed

// #cgo LDFLAGS: -static-libstdc++
import "C"
import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"github.com/GopeedLab/gopeed/pkg/rest"
	"github.com/GopeedLab/gopeed/pkg/rest/model"

	"github.com/ipfs/boxo/files"
	ipfspath "github.com/ipfs/boxo/path"
	"github.com/ipfs/kubo/core/coreapi"
	"github.com/ipfs/kubo/core/coreiface/options"
	ipfs "github.com/marssuren/gomobile_ipfs_0/go/bind/core"
)

// 全局变量，保存IPFS节点和上下文
var (
	ipfsNode    *ipfs.IpfsMobile
	ipfsContext context.Context
	ipfsCancel  context.CancelFunc
)

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

// GetFileFromIPFS 从IPFS获取文件内容
func GetFileFromIPFS(cid string) (string, error) {
	if ipfsNode == nil {
		return "", fmt.Errorf("IPFS node is not running") // 返回更明确的错误
	}

	// 获取API
	api, err := coreapi.NewCoreAPI(ipfsNode.IpfsNode)
	if err != nil {
		return "", fmt.Errorf("failed to get CoreAPI: %w", err)
	}

	// 1. 创建 Path 对象
	p, err := ipfspath.NewPath("/ipfs/" + cid) // 使用 ipfspath.NewPath
	if err != nil {
		return "", fmt.Errorf("failed to create IPFS path: %w", err)
	}

	// 2. 解析路径 (注意 ResolvePath 返回 ImmutablePath, []string, error)
	resolvedPath, _, err := api.ResolvePath(ipfsContext, p) // 忽略 remainderPath
	if err != nil {
		return "", fmt.Errorf("failed to resolve IPFS path %s: %w", p, err)
	}

	// 3. 获取内容
	node, err := api.Unixfs().Get(ipfsContext, resolvedPath) // 使用 resolvedPath
	if err != nil {
		return "", fmt.Errorf("failed to get file node for path %s: %w", resolvedPath, err)
	}

	// 4. 读取内容
	f, ok := node.(files.File)
	if !ok {
		// 如果不是文件类型，可以返回错误或者空字符串，取决于你的需求
		return "", fmt.Errorf("node for path %s is not a file", resolvedPath)
	}
	defer f.Close() // 确保文件被关闭

	// 读取文件所有内容
	contentBytes, err := io.ReadAll(f) // 使用 io.ReadAll 更简洁
	if err != nil {
		return "", fmt.Errorf("failed to read file content from path %s: %w", resolvedPath, err)
	}

	return string(contentBytes), nil
}

// GetIPFSPeerID 获取当前IPFS节点的对等点ID
func GetIPFSPeerID() string {
	if ipfsNode == nil {
		return ""
	}
	return ipfsNode.PeerHost().ID().String()
}
