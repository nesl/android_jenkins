#!/bin/bash
# Called by jenkins_make_android.sh
set -ve
INIT_COMMIT=$(git rev-parse refs/tags/${init_tag}); \
HEAD_COMMIT=$(git rev-parse ${dev_refspec}); \

( \
  echo REPO_PROJECT=${REPO_PROJECT}
  echo "a=refs/tags/${init_tag} ==> ${INIT_COMMIT}"; \
  echo "b=${dev_refspec} ==> ${HEAD_COMMIT}"; \
  echo "git diff ${INIT_COMMIT}..${HEAD_COMMIT}"; \
  git diff ${INIT_COMMIT}..${HEAD_COMMIT}; \
) >${LOG_DIR}/diffs/${REPO_PROJECT////_} 2>&1
