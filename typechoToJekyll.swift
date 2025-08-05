#!/usr/bin/env swift

import Foundation

// MARK: - Data Models
struct TypechoExport: Codable {
    let type: String?
    let version: String?
    let comment: String?
    let name: String?
    let database: String?
    let data: [TypechoPost]?
}

struct TypechoPost: Codable {
    let cid: String
    let title: String
    let slug: String
    let created: String
    let modified: String
    let text: String
    let order: String
    let authorId: String
    let template: String?
    let type: String
    let status: String
    let password: String?
    let commentsNum: String
    let allowComment: String
    let allowPing: String
    let allowFeed: String
    let parent: String
    let views: String
}

// MARK: - Image Downloader
class ImageDownloader {
    private let session: URLSession
    private let downloadSemaphore = DispatchSemaphore(value: 3) // 限制并发下载数
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    func downloadImage(from urlString: String, to localPath: String) -> Bool {
        downloadSemaphore.wait()
        defer { downloadSemaphore.signal() }
        
        // 将HTTPS转换为HTTP
        let httpUrlString = urlString.replacingOccurrences(of: "https://", with: "http://")
        
        guard let url = URL(string: httpUrlString) else {
            print("❌ 无效的URL: \(httpUrlString)")
            return false
        }
        
        print("📡 正在下载: \(url.lastPathComponent) (HTTP)")
        
        let localURL = URL(fileURLWithPath: localPath)
        
        // 如果文件已存在，跳过下载
        if FileManager.default.fileExists(atPath: localPath) {
            print("⏭️  文件已存在，跳过: \(localURL.lastPathComponent)")
            return true
        }
        
        // 创建目录
        let directory = localURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        
        let task = session.downloadTask(with: url) { tempURL, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                print("❌ 下载失败: \(localURL.lastPathComponent) - \(error.localizedDescription)")
                return
            }
            
            guard let tempURL = tempURL else {
                print("❌ 下载失败: \(localURL.lastPathComponent) - 临时文件为空")
                return
            }
            
            do {
                // 如果目标文件已存在，先删除
                if FileManager.default.fileExists(atPath: localPath) {
                    try FileManager.default.removeItem(at: localURL)
                }
                
                try FileManager.default.moveItem(at: tempURL, to: localURL)
                print("✓ 下载成功: \(localURL.lastPathComponent) (HTTP)")
                success = true
            } catch {
                print("❌ 保存失败: \(localURL.lastPathComponent) - \(error.localizedDescription)")
            }
        }
        
        task.resume()
        semaphore.wait()
        
        return success
    }
}

// MARK: - Converter Class
class TypechoToJekyllConverter {
    private let imageDownloader = ImageDownloader()
    
    func convertToJekyll(jsonFilePath: String, outputDirectory: String, downloadImages: Bool = true) throws {
        // 读取JSON文件
        let jsonData = try Data(contentsOf: URL(fileURLWithPath: jsonFilePath))
        
        // 解析JSON
        let exports = try JSONDecoder().decode([TypechoExport].self, from: jsonData)
        
        // 创建输出目录
        let outputURL = URL(fileURLWithPath: outputDirectory)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)
        
        // 找到包含文章数据的部分
        guard let postsExport = exports.first(where: { $0.data != nil }),
              let posts = postsExport.data else {
            throw ConversionError.noPostsFound
        }
        
        // 筛选出type为post的文章
        let postTypePosts = posts.filter { $0.type == "post" }
        
        print("找到 \(postTypePosts.count) 篇文章需要转换")
        
        // 收集所有图片URL
        var allImageUrls: Set<String> = []
        if downloadImages {
            for post in postTypePosts {
                let urls = extractImageUrls(from: post.text)
                allImageUrls.formUnion(urls)
            }
            
            if !allImageUrls.isEmpty {
                print("\n开始下载 \(allImageUrls.count) 张图片...")
                downloadAllImages(imageUrls: Array(allImageUrls), baseDirectory: outputDirectory)
            }
        }
        
        print("\n开始转换文章...")
        
        // 转换每篇文章
        for (index, post) in postTypePosts.enumerated() {
            try convertPost(post, to: outputURL)
            print("✓ [\(index + 1)/\(postTypePosts.count)] 已转换: \(post.title)")
        }
        
        print("\n🎉 转换完成！")
        print("- 共转换 \(postTypePosts.count) 篇文章")
        if downloadImages && !allImageUrls.isEmpty {
            print("- 下载了 \(allImageUrls.count) 张图片")
        }
        print("- 输出目录: \(outputDirectory)")
    }
    
    private func extractImageUrls(from content: String) -> Set<String> {
        var imageUrls: Set<String> = []
        
        // 正则表达式匹配图片URL
        let patterns = [
            // Markdown 图片语法: ![alt](url)
            #"\!\[.*?\]\((https://oss\.wuwz\.net/[^)]+)\)"#,
            // HTML img标签: <img src="url">
            #"<img[^>]+src=["\']?(https://oss\.wuwz\.net/[^"'\s>]+)["\']?"#,
            // 直接的链接
            #"(https://oss\.wuwz\.net/[^\s\)]+)"#
        ]
        
        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let nsContent = content as NSString
                let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
                
                for match in matches {
                    // 获取第一个捕获组（URL）
                    if match.numberOfRanges > 1 {
                        let urlRange = match.range(at: 1)
                        let url = nsContent.substring(with: urlRange)
                        // 清理URL中的转义字符
                        let cleanUrl = url.replacingOccurrences(of: "\\/", with: "/")
                        imageUrls.insert(cleanUrl)
                    }
                }
            } catch {
                print("⚠️  正则表达式错误: \(error)")
            }
        }
        
        return imageUrls
    }
    
    private func downloadAllImages(imageUrls: [String], baseDirectory: String) {
        let dispatchGroup = DispatchGroup()
        var successCount = 0
        var failCount = 0
        let lock = NSLock()
        
        for imageUrl in imageUrls {
            dispatchGroup.enter()
            
            DispatchQueue.global(qos: .utility).async { [weak self] in
                defer { dispatchGroup.leave() }
                
                guard let self = self else { return }
                
                // 生成本地路径
                let localPath = self.generateLocalPath(for: imageUrl, baseDirectory: baseDirectory)
                
                let success = self.imageDownloader.downloadImage(from: imageUrl, to: localPath)
                
                lock.lock()
                if success {
                    successCount += 1
                } else {
                    failCount += 1
                }
                lock.unlock()
            }
        }
        
        dispatchGroup.wait()
        
        print("\n📊 图片下载完成:")
        print("- 成功: \(successCount)")
        print("- 失败: \(failCount)")
        print("- 总计: \(imageUrls.count)")
    }
    
    private func generateLocalPath(for imageUrl: String, baseDirectory: String) -> String {
        // 从URL中提取路径部分，移除域名
        let urlPath = imageUrl.replacingOccurrences(of: "https://oss.wuwz.net", with: "")
        
        // 确保路径以/开头
        let cleanPath = urlPath.hasPrefix("/") ? String(urlPath.dropFirst()) : urlPath
        
        // 组合完整的本地路径
        return "\(baseDirectory)/\(cleanPath)"
    }
    
    private func convertPost(_ post: TypechoPost, to outputURL: URL) throws {
        // 生成Jekyll文件名格式: YYYY-MM-DD-slug.md
        let date = Date(timeIntervalSince1970: TimeInterval(post.created) ?? 0)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        let fileName = "\(dateString)-\(post.slug).md"
        let fileURL = outputURL.appendingPathComponent(fileName)
        
        // 生成Jekyll Front Matter
        let frontMatter = generateFrontMatter(for: post)
        
        // 处理文章内容
        let processedContent = processContent(post.text)
        
        // 组合完整内容
        let fullContent = frontMatter + processedContent
        
        // 写入文件
        try fullContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func generateFrontMatter(for post: TypechoPost) -> String {
        let createdDate = Date(timeIntervalSince1970: TimeInterval(post.created) ?? 0)
        let modifiedDate = Date(timeIntervalSince1970: TimeInterval(post.modified) ?? 0)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        
        let createdString = dateFormatter.string(from: createdDate)
        let modifiedString = dateFormatter.string(from: modifiedDate)
        
        var frontMatter = """
---
layout: post
title: "\(escapeYamlString(post.title))"
date: \(createdString)
modified: \(modifiedString)
slug: \(post.slug)
categories: []
tags: []
comments: \(post.allowComment == "1" ? "true" : "false")
views: \(post.views)
---

"""
        
        return frontMatter
    }
    
    private func processContent(_ content: String) -> String {
        var processedContent = content
        
        // 移除Typecho的markdown标记
        processedContent = processedContent.replacingOccurrences(of: "<!--markdown-->", with: "")
        
        // 处理图片URL - 移除https://oss.wuwz.net
        processedContent = processedContent.replacingOccurrences(
            of: "https://oss.wuwz.net",
            with: ""
        )
        
        // 处理转义的斜杠
        processedContent = processedContent.replacingOccurrences(of: "\\/", with: "/")
        
        // 处理换行符
        processedContent = processedContent.replacingOccurrences(of: "\\r\\n", with: "\n")
        processedContent = processedContent.replacingOccurrences(of: "\\n", with: "\n")
        processedContent = processedContent.replacingOccurrences(of: "\r\n", with: "\n")
        
        return processedContent
    }
    
    private func escapeYamlString(_ string: String) -> String {
        return string.replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - Error Types
enum ConversionError: Error {
    case noPostsFound
    case invalidJSONFormat
    
    var localizedDescription: String {
        switch self {
        case .noPostsFound:
            return "未找到文章数据"
        case .invalidJSONFormat:
            return "JSON格式无效"
        }
    }
}

// MARK: - Main Execution
func main() {
    let arguments = CommandLine.arguments
    
    guard arguments.count >= 2 else {
        print("""
使用方法:
swift typecho_to_jekyll.swift <JSON文件路径> [输出目录] [--no-download]

参数:
  JSON文件路径    - Typecho导出的JSON文件路径
  输出目录        - Jekyll文章输出目录 (可选，默认为 ./jekyll_posts)
  --no-download   - 不下载图片 (可选)

示例:
swift typecho_to_jekyll.swift typechoToJekyll.json
swift typecho_to_jekyll.swift typechoToJekyll.json ./my_posts
swift typecho_to_jekyll.swift typechoToJekyll.json ./my_posts --no-download
""")
        return
    }
    
    let jsonFilePath = arguments[1]
    let outputDirectory = arguments.count > 2 && !arguments[2].hasPrefix("--") ? arguments[2] : "./jekyll_posts"
    let downloadImages = !arguments.contains("--no-download")
    
    // 检查输入文件是否存在
    guard FileManager.default.fileExists(atPath: jsonFilePath) else {
        print("❌ 错误: 找不到文件 '\(jsonFilePath)'")
        return
    }
    
    print("🚀 开始转换...")
    print("- 输入文件: \(jsonFilePath)")
    print("- 输出目录: \(outputDirectory)")
    print("- 下载图片: \(downloadImages ? "是" : "否")")
    print()
    
    let converter = TypechoToJekyllConverter()
    
    do {
        try converter.convertToJekyll(
            jsonFilePath: jsonFilePath, 
            outputDirectory: outputDirectory,
            downloadImages: downloadImages
        )
    } catch {
        print("❌ 转换失败: \(error.localizedDescription)")
    }
}

// 运行主程序
main()