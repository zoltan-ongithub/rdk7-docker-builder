# RDK-7 Build Environment Configuration
# Generated on ${timestamp.isoformat()}

# Target configuration
export TARGET="${build['target']}"
export LAYER="${target_layer}"
export MANIFEST_BRANCH="${build['branch']['manifest']}"
export OSS_BRANCH="${build['branch']['oss']}"

# Layer directories (uses container paths)
% for layer_name, layer in layers.items():
export ${env_prefix[layer_name]}_DIR="${build['workspace-dir']}/${layer_name}-layer"
% endfor

# IPK feed paths (uses container paths)
% for layer_name, layer in layers.items():
% if layer_name == 'oss':
export ${env_prefix[layer_name]}_IPK_PATH="${build['shared-dir']}/${build['machine']['arch']}-${layer_name}/${build['branch']['oss']}/ipk"
% elif layer_name != 'image-assembler':
export ${env_prefix[layer_name]}_IPK_PATH="${build['shared-dir']}/${build['machine']['model']}-${layer_name}/${build['branch']['manifest']}/ipk"
% endif
% endfor

# Repository configuration
export REPO_TYPE="${repository['type']}"
export REPO_BASE_URL="${repository['base-url']}"

# IPK server URLs (remote paths matching local structure)
% for layer_name, layer in layers.items():
% if layer_name == 'oss':
export ${env_prefix[layer_name]}_IPK_SERVER_URL="${repository['base-url']}/${build['machine']['arch']}-${layer_name}/${build['branch']['oss']}/ipk"
% elif layer_name != 'image-assembler':
export ${env_prefix[layer_name]}_IPK_SERVER_URL="${repository['base-url']}/${build['machine']['model']}-${layer_name}/${build['branch']['manifest']}/ipk"
% endif
% endfor

# Build setup (uses container paths)
% if target_layer == 'oss':
export MACHINE="${build['machine']['arch']}"
% else:
export MACHINE="${build['machine']['model']}"
% endif
export BUILD_COMMAND="${layers[target_layer]['build-command']}"
export BUILD_DIR="build-$MACHINE"
export WORK_DIR="$${env_prefix[target_layer]}_DIR"

<%
    from urllib.parse import urlparse
    from pathlib import Path
%>
# Manifest URLs and files
% for layer_name, layer in layers.items():
<%
    url = urlparse(layer['manifest'])
    path = Path(url.path)
%>
export ${env_prefix[layer_name]}_MANIFEST_URL="${url.scheme}://${url.netloc}${path.parent}"
export ${env_prefix[layer_name]}_MANIFEST_FILE="${path.name}"
% endfor

echo "RDK-7 build environment loaded for $TARGET/$LAYER"
echo "Work directory: $WORK_DIR"
echo "Build directory: $BUILDDIR"
echo "Machine: $MACHINE"
echo "Build command: $BUILD_COMMAND"
