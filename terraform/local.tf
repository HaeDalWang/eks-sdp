# 로컬 환경변수 지정
locals {
  project             = "eks-sdp"
  service_domain_name = "${var.domain_name}"
  tags                = {}
}

# 화이트리스트 목록
locals {
  whitelist_ip_range = [
    "121.140.122.206/32", # 솔트웨어
    "0.0.0.0/0"           # 임시
  ]
}