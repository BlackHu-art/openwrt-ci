# 修改默认IP & 固件名称 & 编译署名 & 修正vlmcsd的hash值
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='OpenWrt'/g" package/base-files/files/bin/config_generate
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ Build by OpenWrt')/g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# 升级AriaNG到v1.3.11
sed -i -e 's/PKG_VERSION:=1.3.10/PKG_VERSION:=1.3.11/' \
       -e 's/PKG_HASH:=5b76f02ff208b8c948bf8b614511687b7e6d1562323b29494528d89c032fe086/PKG_HASH:=deaaebaf8d59901f0fbdb839daceb1f2768b3d65425e393202786fa2c804bcf9/' \
          feeds/packages/net/ariang/Makefile

# 升级frp到v0.63.0
sed -i -e 's/^PKG_VERSION:=0\.51\.3$/PKG_VERSION:=0.63.0/' \
       -e 's/^PKG_HASH:=83032399773901348c660d41c967530e794ab58172ccd070db89d5e50d915fef$/PKG_HASH:=e5269cf3d545a90fe3773dd39abe6eb8511f02c1dc0cdf759a65d1e776dc1520/' \
       -e 's#\(\$(INSTALL_DATA) \$(PKG_BUILD_DIR)/\)conf/\(\$(2)\)_full.ini#\1conf/legacy/\2_legacy_full.ini#' \
       -e '/\$(INSTALL_DATA) \$(PKG_BUILD_DIR)\/conf\/legacy\/\$(2)_legacy_full.ini/a \\t$(INSTALL_DATA) $(PKG_BUILD_DIR)/conf/$(2)_full_example.toml $(1)/etc/frp/$(2).d/' \
          feeds/packages/net/frp/Makefile

# 调整NSS驱动q6_region内存区域预留大小（ipq6018.dtsi默认预留85MB，ipq6018-512m.dtsi默认预留55MB，带WiFi必须至少预留54MB，以下分别是改成预留16MB、32MB、64MB和96MB）
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x01000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x02000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x04000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x06000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi

# 移除要替换的包
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/luci/applications/luci-app-appfilter
rm -rf feeds/packages/net/adguardhome
rm -rf feeds/packages/net/speedtest-cli


# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# Go & AList & AdGuardHome & AriaNg & WolPlus & Lucky & OpenAppFilter & 集客无线AC控制器 & 雅典娜LED控制
git clone --depth=1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist
git clone --depth=1 https://github.com/sirpdboy/luci-app-netspeedtest package/netspeedtest
git clone --depth=1 https://github.com/sirpdboy/luci-app-partexp.git package/luci-app-partexp
git clone --depth=1 https://github.com/esirplayground/luci-app-poweroff package/luci-app-poweroff
git_sparse_clone master https://github.com/kenzok8/openwrt-packages adguardhome luci-app-adguardhome
git_sparse_clone main https://github.com/VIKINGYFY/packages luci-app-wolplus
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter
git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac package/openwrt-gecoosac
# git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
# chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

./scripts/feeds update -a
./scripts/feeds install -a
