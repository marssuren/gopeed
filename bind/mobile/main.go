package libgopeed

// #cgo LDFLAGS: -static-libstdc++
import "C"
import (
	"encoding/json"

	"github.com/GopeedLab/gopeed/pkg/rest"
	"github.com/GopeedLab/gopeed/pkg/rest/model"

	// 导入IPFS核心包
	ipfs "github.com/ipfs-shipyard/gomobile-ipfs/go/bind/core"
)

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

// 新增IPFS功能

// StartIPFSNode 启动IPFS节点
func StartIPFSNode(repoPath string) (string, error) {
	// 创建IPFS节点配置
	cfg := ipfs.NewNodeConfig()
	// 设置仓库路径
	cfg.SetRepoPath(repoPath)

	// 创建并启动节点
	node, err := ipfs.NewNode(cfg)
	if err != nil {
		return "", err
	}

	// 返回节点ID
	return node.Identity().Pretty(), nil
}

// StopIPFSNode 停止IPFS节点
func StopIPFSNode(node *ipfs.Node) error {
	if node != nil {
		return node.Close()
	}
	return nil
}
