IMAGE = nestorsalceda/falco-operator
# Use same version than helm chart
PREVIOUS_VERSION = $(shell ls -d deploy/olm-catalog/sysdig-operator/*/ -t | head -n1 | cut -d"/" -f4)
VERSION = 1.1.9
CERTIFIED_IMAGE = registry.connect.redhat.com/sysdig/falco-operator

#CERTIFIED_AGENT_IMAGE = registry.connect.redhat.com/sysdig/agent
#AGENT_VERSION = 9.9.1

.PHONY: build bundle.yaml

build: update-chart
	operator-sdk build $(IMAGE):$(VERSION)

update-chart:
	rm -fr helm-charts/falco
	helm repo add falcosecurity https://falcosecurity.github.io/charts
	helm fetch falcosecurity/falco --version $(VERSION) --untar --untardir helm-charts/

push:
	docker push $(IMAGE):$(VERSION)

bundle.yaml:
	cat deploy/crds/falco.org_falcos_crd.yaml > bundle.yaml
	echo '---' >> bundle.yaml
	cat deploy/service_account.yaml >> bundle.yaml
	echo '---' >> bundle.yaml
	cat deploy/role_binding.yaml >> bundle.yaml
	echo '---' >> bundle.yaml
	cat deploy/operator.yaml >> bundle.yaml
	sed -i 's|REPLACE_IMAGE|docker.io/$(IMAGE):$(VERSION)|g' bundle.yaml

e2e: bundle.yaml
	oc apply -f bundle.yaml
	oc apply -f deploy/crds/falco.org_v1_falco_cr.yaml

e2e-clean: bundle.yaml
	oc delete -f deploy/crds/falco.org_v1_falco_cr.yaml
	oc delete -f bundle.yaml

package-redhat:
	cp deploy/crds/sysdig_v1_sysdig_crd.yaml redhat-certification/sysdig.crd.yaml
	cp redhat-certification/sysdig-operator.vX.X.X.clusterserviceversion.yaml redhat-certification/sysdig-operator.v${VERSION}.clusterserviceversion.yaml
	\
	sed -i 's|REPLACE_VERSION|${VERSION}|g' redhat-certification/sysdig-operator.v${VERSION}.clusterserviceversion.yaml
	sed -i 's|REPLACE_IMAGE|${CERTIFIED_IMAGE}|g' redhat-certification/sysdig-operator.v${VERSION}.clusterserviceversion.yaml
	sed -i 's|REPLACE_AGENT_IMAGE|${CERTIFIED_AGENT_IMAGE}|g' redhat-certification/sysdig-operator.v${VERSION}.clusterserviceversion.yaml
	sed -i 's|REPLACE_AGENT_VERSION|${AGENT_VERSION}|g' redhat-certification/sysdig-operator.v${VERSION}.clusterserviceversion.yaml
	sed -i 's|REPLACE_VERSION|${VERSION}|g' redhat-certification/sysdig.package.yaml
	\
	zip -j redhat-certification-metadata-${VERSION}.zip \
		redhat-certification/sysdig-operator.v${VERSION}.clusterserviceversion.yaml \
		redhat-certification/sysdig.crd.yaml \
		redhat-certification/sysdig.package.yaml
	\
	rm	redhat-certification/sysdig.crd.yaml \
		redhat-certification/sysdig-operator.v${VERSION}.clusterserviceversion.yaml
	\
	git checkout redhat-certification

new-upstream: bundle.yaml build push operatorhub package-redhat
	sed -i "s/^VERSION = .*/VERSION = $(VERSION)/" Makefile
	git add bundle.yaml
	git add Makefile
	git commit -m "New Sysdig helm chart release $(VERSION)"
	git tag -f v$(VERSION)
	GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" git push origin HEAD:master
	GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" git push --tags -f

operatorhub:
	mkdir -p deploy/olm-catalog/sysdig-operator/$(VERSION)
	cp deploy/olm-catalog/sysdig-operator/sysdig-operator.template.clusterserviceversion.yaml deploy/olm-catalog/sysdig-operator/$(VERSION)/sysdig-operator.v$(VERSION).clusterserviceversion.yaml
	sed -i "s/AGENT_VERSION/$(AGENT_VERSION)/" deploy/olm-catalog/sysdig-operator/$(VERSION)/sysdig-operator.v$(VERSION).clusterserviceversion.yaml
	sed -i "s/PREVIOUS_VERSION/$(PREVIOUS_VERSION)/" deploy/olm-catalog/sysdig-operator/$(VERSION)/sysdig-operator.v$(VERSION).clusterserviceversion.yaml
	sed -i "s/VERSION/$(VERSION)/" deploy/olm-catalog/sysdig-operator/$(VERSION)/sysdig-operator.v$(VERSION).clusterserviceversion.yaml
	git add deploy/olm-catalog/sysdig-operator/$(VERSION)/sysdig-operator.v$(VERSION).clusterserviceversion.yaml
