define DOWNLOAD_GIT_WITH_SUBMODULES
	test -e $(DL_DIR)/$($(PKG)_SOURCE) || \
	(pushd $(DL_DIR) > /dev/null && \
	 ((test "`git ls-remote $($(PKG)_SITE) $($(PKG)_DL_VERSION)`" && \
	   echo "Doing clone and initialize submodules" && \
	   $(GIT) clone --depth 1 -b $($(PKG)_DL_VERSION) --recurse-submodules $($(PKG)_SITE) $($(PKG)_BASE_NAME)) || \
	  (echo "Doing full clone and initialize submodules" && \
	   $(GIT) clone $($(PKG)_SITE) $($(PKG)_BASE_NAME) && \
	   cd  $($(PKG)_BASE_NAME) && $(GIT) checkout  $($(PKG)_DL_VERSION) && \
	   $(GIT) submodule init && \
	   $(GIT) submodule sync && \
	   $(GIT) submodule update && \
	   cd ..)) && \
	pushd $($(PKG)_BASE_NAME) > /dev/null && \
	$(TAR) cf $(DL_DIR)/.$($(PKG)_SOURCE).tmp . ; \
	gzip -c $(DL_DIR)/.$($(PKG)_SOURCE).tmp > $(DL_DIR)/$($(PKG)_SOURCE) && \
	rm -f $(DL_DIR)/.$($(PKG)_SOURCE).tmp && \
	popd > /dev/null && \
	rm -rf $($(PKG)_DL_DIR) && \
	popd > /dev/null)
endef

define DOWNLOAD_INNER
	$(Q)if test -n "$(call qstrip,$(BR2_PRIMARY_SITE))" ; then \
		case "$(call geturischeme,$(BR2_PRIMARY_SITE))" in \
			file) $(call $(3)_LOCALFILES,$(BR2_PRIMARY_SITE)/$(2),$(2)) && exit ;; \
			scp) $(call $(3)_SCP,$(BR2_PRIMARY_SITE)/$(2),$(2)) && exit ;; \
			*) $(call $(3)_WGET,$(BR2_PRIMARY_SITE)/$(2),$(2)) && exit ;; \
		esac ; \
	fi ; \
	if test "$(BR2_PRIMARY_SITE_ONLY)" = "y" ; then \
		exit 1 ; \
	fi ; \
	if test -n "$(1)" ; then \
		case "$($(PKG)_SITE_METHOD)" in \
			git) $($(3)_GIT) && exit ;; \
			git_with_submodules) $($(3)_GIT_WITH_SUBMODULES) && exit ;; \
			svn) $($(3)_SVN) && exit ;; \
			cvs) $($(3)_CVS) && exit ;; \
			bzr) $($(3)_BZR) && exit ;; \
			file) $($(3)_LOCALFILES) && exit ;; \
			scp) $($(3)_SCP) && exit ;; \
			hg) $($(3)_HG) && exit ;; \
			*) $(call $(3)_WGET,$(1),$(2)) && exit ;; \
		esac ; \
	fi ; \
	if test -n "$(call qstrip,$(BR2_BACKUP_SITE))" ; then \
		$(call $(3)_WGET,$(BR2_BACKUP_SITE)/$(2),$(2)) && exit ; \
	fi ; \
	exit 1
endef
include $(BR2_EXTERNAL)/package/external.mk
