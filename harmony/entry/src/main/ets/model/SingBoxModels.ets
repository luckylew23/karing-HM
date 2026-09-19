/**
 * sing-box 配置模型类型别名
 * ArkTS 限制：不支持索引签名接口 / 结构类型 / 索引字段访问，
 * 因此配置构建统一使用 Record<string, Object> + 显式变量（见 SingBoxConfigBuilder）。
 * 本文件保留命名导出以便文档与后续 native 桥接引用。
 */

/** 通用 JSON 对象 */
export type JsonMap = Record<string, Object>;
