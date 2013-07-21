#!/bin/bash
# Author: Kasturi Raghavan (kastur@gmail.com)

# Required args:
# (Usually provided by jenkin) JOB_NAME, BRANCH_JOB, BUILD_NUMBER
# init_tag
# dev_refspec
# local_manifest
# dev_projects
# lunch

set -e
set +xv

DONE_ASCII='
---------------------------------
  ____     ___    _   _   _____ 
 |  _ \   / _ \  | \ | | | ____|
 | | | | | | | | |  \| | |  _|  
 | |_| | | |_| | | |\  | | |___ 
 |____/   \___/  |_| \_| |_____|
---------------------------------
'

FAIL_ASCII='
---------------------------------
  _____      _      ___   _     
 |  ___|    / \    |_ _| | |    
 | |_      / _ \    | |  | |    
 |  _|    / ___ \   | |  | |___ 
 |_|     /_/   \_\ |___| |_____|
---------------------------------
'
function fail() {
  echo "${FAIL_ASCII}"
}

trap "fail" EXIT

echo "Setting up variables"
export LANG='en_US.UTF-8'  # The default ASCII encoding causes javac errors.
export USE_CCACHE=1
export CCACHE_DIR=/scratch/aosp/ccache

PUBLIC_FQDN=android.0x72.com
JOB_URL=http://${PUBLIC_FQDN}:8080/job/${JOB_NAME}/
REPO=/aosp/bin/repo
#ANNOTATE="annotate-output +%Y-%m-%d-%H:%M:%S.%N"
ANNOTATE= # Disabled for now.
FLOCK=flock
VERBOSE=verbose

if [[ FLAG_use_mirror == "true" && -d /aosp/mirror/platform/manifest.git ]]; then
  INIT_URL=/aosp/mirror/platform/manifest.git
else
  INIT_URL=https://android.googlesource.com/platform/manifest
fi

# Replace "/" since we don't want to create nested directories.
BRANCH_JOB="${JOB_NAME}-${dev_refspec////_}"
BRANCH_JOB_NUMBERED=${BRANCH_JOB}-${BUILD_NUMBER}
LOG_DIR=$WORKSPACE/logs/${BRANCH_JOB_NUMBERED}
BUILD_DIR=/scratch/aosp/android  # Used to be based on BRANCH_JOB, but no longer.
export TMPDIR=${BUILD_DIR}/tmp  # used by mktemp
LOCK_FILE=${BUILD_DIR}/LOCK
OUT_COPY_DIR=$WORKSPACE/copy/${BRANCH_JOB_NUMBERED}
SDK_COPY_DIR=$WORKSPACE/copy/${BRANCH_JOB_NUMBERED}

# The LOG_DIR should be unique (i.e. build numbered), but clean to be sure.
set -v
mkdir -p ${BUILD_DIR} 
cd ${BUILD_DIR}

rm -rf ${TMPDIR}
mkdir ${TMPDIR}

rm -rf ${LOG_DIR} 
mkdir -p ${LOG_DIR}
set +v

function log() {
  echo $@ >&7
}

function print_log_urls() {
  log '-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-'
  for log in $@; do
  log STREAMING LOGS $log ${JOB_URL}ws/logs/${BRANCH_JOB_NUMBERED}/$log/'*view*'
  done;
  log '-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-'
}


function logz_url() {
  if [[ FLAG_interactive == "true" ]]; then
    log '>>logz' $1 '<'${LOG_DIR}/$1'>'
  else 
    log '>>logz' $1 '<'${JOB_URL}ws/logs/${BRANCH_JOB_NUMBERED}/$1/'*view*>'
  fi
}

if [[ FLAG_color == "true" ]]; then
bold=`tput bold`
normal=`tput sgr0`
blue=`tput setaf 4`
fi

function logz() {
  log '+ ' "${bold}${blue}${@:2}${normal}"
  logz_url "${bold}$1${normal}"
  eval "${@:2}" 2>&1 | pv -tb -i10 2>&7 | tee -a ${LOG_DIR}/$1 2>&1 > /dev/null
  ret=$?
  if [[ $ret -ne 0 ]]; then
    log "${bold}RETURN CODE=$ret${normal}"
    log "======== LAST 100 lines of $1 ======="
    tail -n 100 ${LOG_DIR}/$1 >&7
    log "============================================"
    ls -lth ${LOG_DIR} >&7
    exit $ret
  fi
  return $ret
}

# Acquire lock to prevent two builds on same BUILD_DIR
(
7<>`mktemp`
log "Waiting for lock."
$FLOCK --wait=$(( 3600 * 3 )) 9  # Wait for upto 3 hours to obtain lock.
log "Acquired exclusive lock."

# Put a symbolic link to the build directory in jenkins workspace.
rm -f $WORKSPACE/build_directory
ln -s ${BUILD_DIR} $WORKSPACE/build_directory

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
echo SYSTEM DASHBOARD : http://${PUBLIC_FQDN}:8000/cgi/dash
echo STREAMING LOGS TO: ${JOB_URL}ws/logs/${BRANCH_JOB_NUMBERED}/
echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

logz SETUP_ENV env
logz SETUP_ENV java -version

(
if [[ ${FLAG_NO_SYNC} != "true" ]]; then 

  # Remove .repo/local_manifest.xml and .repo/local_manifests directory.
  rm -rf .repo/local_manifest*

  logz sync_init $ANNOTATE $REPO init \
      -u ${INIT_URL} -b ${init_tag}
  logz sync_aosp $ANNOTATE $REPO sync -j8

  # Put override to github and sync again.
  mkdir .repo/local_manifests;
  echo "${local_manifest}" > .repo/local_manifests/override.xml
  logz sync_override_xml cat .repo/local_manifests/override.xml
  logz sync_github $ANNOTATE $REPO sync -j8

  # Checkout the head commit hash of each non-aosp repo.
  logz sync_checkout $REPO forall ${dev_projects} \
      -c git checkout ${dev_refspec}

  # TODO(krr): do a reset --hard here ?

  # If making for MAKO, then extract proprietary drivers.
  if echo "$lunch" | grep -q mako; then
   log "Extracting drivers."
   logz sync_drivers tar -xvf /aosp/bin/mako_drivers.tar.gz
  fi
fi

# Output the full code diff from init_tag to checked out code
# just for affected repos
log "Producing diffs"
mkdir ${LOG_DIR}/diffs
$ANNOTATE $REPO forall ${dev_projects} \
    -c "LOG_DIR=${LOG_DIR} /aosp/bin/jenkins_make_android_diff.sh"

echo "Doing a repo status and git log -n1" >&7
# Output the latest commit hash for each project.
logz sync_finish_ls ls -la
logz sync_finish_repo_status $REPO status 
logz sync_finish_gitlog $REPO forall frameworks/native -c "'"'echo ${REPO_PROJECT} $(git log -n1 --pretty=oneline)'"'"

) >${LOG_DIR}/SYNC 2>&1

logz_url BUILD
(
log Doing lunch $lunch
source build/envsetup.sh
lunch $lunch

# Log execution environment after lunch.
logz build_env env; \
logz build_env java -version 2>&1; \
logz build_env prebuilts/misc/linux-x86/ccache/ccache -s; \

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

test ${FLAG_NO_CLOBBER} == "true" ||
    logz build_clean $ANNOTATE make clobber

test ${FLAG_UPDATE_API} == "false" ||  
    logz build_api $ANNOTATE make update-api

logz build_real $ANNOTATE make -j8

# Since we have 'set -e', SUCCESSFUL will only be created if above succeeds.
touch ${LOG_DIR}/SUCCESSFUL
) >${LOG_DIR}/BUILD 2>&1

logz_url POST_BUILD
(
# Copy the 'out/' folder over to workspace,
# make sure this is persistent storage!
if [[ ${FLAG_copy_out} == "true" ]]; then
  mkdir -p ${OUT_COPY_DIR}
  cp -r out ${OUT_COPY_DIR}
  touch ${LOG_DIR}/SUCCESSFUL-COPY
fi
) >${LOG_DIR}/POST_BUILD 2>&1

echo "${DONE_ASCII}"
trap - EXIT
) 7>&1 9> ${LOCK_FILE}
