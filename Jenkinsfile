// Snyk differential scan. 
//
// Use instead of the Snyk platform's native PR check,
// don't run both on the same repo or you'll get duplicate/conflicting
// results.
//
// Jenkins plugin only covers Open Source (SCA). Code, Container, and IaC
// go through the CLI.
//
// What runs when (Multibranch Pipeline gives us BRANCH_NAME / CHANGE_ID /
// CHANGE_TARGET):
//   - feature branch push -> Quick scan, doesn't block anything
//   - PR into main/release -> Gate. SCA checks only new issues vs
//     baseline, SAST/IaC only look at changed files. Any failure blocks merge.
//   - push to main/release -> Full scan, sets the new baseline, builds and
//     scans the container image
//
// Setup needed (see JENKINS-SETUP.md):
//   - Snyk Security plugin, tool installation named 'snyk-latest'
//   - NodeJS plugin, tool named 'node18'
//   - 'snyk-token' secret text cred (both the plugin and CLI expect
//     SNYK_TOKEN in the env)
//   - Docker on the agent for the container stage
//   - Snyk Code turned on for the org

pipeline {
  agent any

  tools {
    nodejs 'node18'
  }

  environment {
    SNYK_TOKEN        = credentials('snyk-token')
    SNYK_INSTALLATION = 'snyk-latest'               // Manage Jenkins > Tools
    IMAGE             = "nodejs-goof:${env.BUILD_NUMBER}"
  }

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  stages {

    // Installs deps and the CLI tools the later stages need.
    stage('Setup') {
      steps {
        sh 'node -v && npm -v'
        sh 'npm install --ignore-scripts'
        sh 'npm install -g snyk snyk-delta snyk-to-html'
      }
    }

    // Feature branches get a fast, non-blocking pass so devs get early feedback without being blocked before there's even a PR open.
    stage('Quick scan (feature branch)') {
      when {
        allOf {
          not { changeRequest() }
          not { branch 'main' }
          not { branch pattern: 'release/*', comparator: 'GLOB' }
        }
      }
      steps {
        // SCA through the plugin. failOnIssues:false and no monitor since
        // this is just a heads up, not a gate.
        snykSecurity(
          snykInstallation: env.SNYK_INSTALLATION,
          severity: 'high',
          failOnIssues: false,
          monitorProjectOnBuild: false
        )
        // Code + IaC through the CLI. `|| true` keeps these advisory only.
        sh 'snyk code test --severity-threshold=high || true'
        sh 'snyk iac test  --severity-threshold=high || true'
      }
    }

    // This is the actual gate. Merges get blocked here, not on feature
    // branches.
    //
    // SCA uses snyk-delta so we only fail on NEW issues vs whatever's already
    // monitored on main, not the whole existing backlog. Code/IaC don't have
    // a delta mode, so we fake it by diffing changed files against the PR
    // target branch and only scanning those.
    stage('Differential gate (PR)') {
      when { changeRequest() }
      steps {
        // --setPassIfNoBaseline true matters here: without it, the very
        // first PR on a repo with no baseline yet would fail on everything.
        sh 'snyk test --json --print-deps --severity-threshold=high | snyk-delta --setPassIfNoBaseline true'

        sh '''
          set -e
          git fetch origin "$CHANGE_TARGET" --depth=1
          CODE=$(git diff --name-only "origin/$CHANGE_TARGET"...HEAD | grep -E '\\.(js|jsx|ts|tsx)$' || true)
          IAC=$(git diff --name-only "origin/$CHANGE_TARGET"...HEAD | grep -E '\\.(tf|ya?ml|json)$|Dockerfile' || true)
          if [ -n "$CODE" ]; then echo "Scanning changed code:"; echo "$CODE"; echo "$CODE" | tr '\\n' ' ' | xargs snyk code test --severity-threshold=high; fi
          if [ -n "$IAC" ];  then echo "Scanning changed IaC:";  echo "$IAC";  echo "$IAC"  | tr '\\n' ' ' | xargs snyk iac test  --severity-threshold=high; fi
        '''
      }
    }

    // Runs on push to main/release. Full scan of everything, and this is
    // what sets the baseline snyk-delta compares against on the next PR.
    //
    // failOnIssues is false here on purpose. main will always have some
    // backlog of known issues and we don't want that turning the pipeline
    // red forever, the PR gate above is already catching new stuff.
    stage('Baseline (protected branch)') {
      when {
        anyOf {
          branch 'main'
          branch pattern: 'release/*', comparator: 'GLOB'
        }
      }
      steps {
        // monitorProjectOnBuild:true is what actually writes the baseline
        // snapshot to the Snyk platform. If this repo is also SCM-imported
        // on the platform side, turn this off or you'll get a duplicate
        // project.
        snykSecurity(
          snykInstallation: env.SNYK_INSTALLATION,
          severity: 'high',
          failOnIssues: false,
          monitorProjectOnBuild: true,
          projectName: 'nodejs-goof'
        )

        sh 'snyk code test --severity-threshold=high || true'
        sh 'snyk iac test  --severity-threshold=high || true'

        // Container scan only makes sense once we have an actual image,
        // which is why this only happens here and not on PRs.
        sh "docker build -t ${IMAGE} ."
        sh "snyk container test    ${IMAGE} --file=Dockerfile --severity-threshold=high || true"
        sh "snyk container monitor ${IMAGE} --file=Dockerfile"
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: '**/snyk*.html, **/*.sarif', allowEmptyArchive: true
    }
  }
}
