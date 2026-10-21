//
//  CameraPosition.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 相机采集使用的镜头方向。
public enum CameraPosition: String, CaseIterable, Sendable {

    /// 前置摄像头。
    case front

    /// 后置摄像头。
    case back
}
