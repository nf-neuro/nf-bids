#!/bin/bash
# Validation test runner based on nf-test suites.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PLUGIN_VERSION="0.1.0-beta.10"
PLUGINS_DIR="${NXF_PLUGINS_DIR:-$HOME/.nextflow/plugins}"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [DATASETS...]

Run validation suites via nf-test.

OPTIONS:
    -h, --help                Show this help message
    -v, --verbose             Show full Nextflow output from nf-test
    -c, --custom              Run only custom-dataset validation suites
    -b, --bids                Run only BIDS-examples validation suites
    -l, --list                List datasets and their suite mapping
        --update-snapshots    Re-record failing snapshots
        --clean-snapshots     Remove obsolete snapshots
        --ci                  Fail on snapshot differences (CI behavior)
        --dry-run             Discover tests without executing them

DATASETS:
    Optional dataset names (e.g. ds-dwi qmri_irt1).
    Dataset selection is mapped to nf-test suite files.

EXAMPLES:
    $0
    $0 --update-snapshots
    $0 -c
    $0 ds-dwi qmri_irt1
    $0 -v --clean-snapshots
EOF
}

bootstrap_runtime() {
    echo "[bootstrap] Ensuring nf-bids plugin is installed..."
    (cd "${REPO_ROOT}" && ./gradlew install >/dev/null)

    if [[ ! -d "${PLUGINS_DIR}/nf-bids-${PLUGIN_VERSION}" ]]; then
        echo "[bootstrap] ERROR: nf-bids plugin missing at ${PLUGINS_DIR}/nf-bids-${PLUGIN_VERSION}"
        exit 1
    fi

    if [[ ! -f "${REPO_ROOT}/libBIDS.sh/libBIDS.sh" ]]; then
        echo "[bootstrap] Initializing libBIDS.sh submodule..."
        (cd "${REPO_ROOT}" && git submodule update --init --recursive libBIDS.sh >/dev/null)
    fi

    if [[ ! -f "${REPO_ROOT}/libBIDS.sh/libBIDS.sh" ]]; then
        echo "[bootstrap] ERROR: libBIDS.sh not found at ${REPO_ROOT}/libBIDS.sh/libBIDS.sh"
        exit 1
    fi
}

resolve_nf_test_cmd() {
    if nf-test version >/dev/null 2>&1; then
        NF_TEST_CMD=(nf-test)
        return
    fi

    local jar_path="$HOME/.nf-test/nf-test.jar"
    if [[ -f "${jar_path}" ]]; then
        NF_TEST_CMD=(java -jar "${jar_path}")
        return
    fi

    echo "[bootstrap] ERROR: nf-test is not runnable."
    echo "[bootstrap] Expected either:"
    echo "  - a working nf-test launcher in PATH"
    echo "  - or ${jar_path}"
    echo "[bootstrap] Try: nf-test update"
    exit 1
}

# Parse arguments
VERBOSE=false
CUSTOM_ONLY=false
BIDS_ONLY=false
LIST_ONLY=false
UPDATE_SNAPSHOTS=false
CLEAN_SNAPSHOTS=false
CI_MODE=false
DRY_RUN=false
SPECIFIC_DATASETS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -c|--custom)
            CUSTOM_ONLY=true
            shift
            ;;
        -b|--bids)
            BIDS_ONLY=true
            shift
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        --update-snapshots)
            UPDATE_SNAPSHOTS=true
            shift
            ;;
        --clean-snapshots)
            CLEAN_SNAPSHOTS=true
            shift
            ;;
        --ci)
            CI_MODE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            SPECIFIC_DATASETS+=("$1")
            shift
            ;;
    esac
done

if [[ "${CUSTOM_ONLY}" == true && "${BIDS_ONLY}" == true ]]; then
    echo "Cannot use --custom and --bids together"
    exit 1
fi

# Dataset -> nf-test suite mapping
declare -A DATASET_TO_SUITE=(
    [ds-dwi]="test/validation/comparison_custom_datasets.nf.test"
    [ds-dwi2]="test/validation/comparison_custom_datasets.nf.test"
    [ds-dwi3]="test/validation/comparison_custom_datasets.nf.test"
    [ds-dwi4]="test/validation/comparison_custom_datasets.nf.test"
    [ds-mrs_fmrs]="test/validation/comparison_custom_datasets.nf.test"
    [ds-mtsat]="test/validation/comparison_custom_datasets.nf.test"
    [asl001]="test/validation/comparison_plain_sets.nf.test"
    [asl002]="test/validation/comparison_plain_sets.nf.test"
    [eeg_cbm]="test/validation/comparison_plain_sets.nf.test"
    [qmri_mtsat]="test/validation/comparison_named_sets.nf.test"
    [qmri_tb1tfl]="test/validation/comparison_named_sets.nf.test"
    [qmri_vfa]="test/validation/comparison_sequential_sets.nf.test"
    [qmri_irt1]="test/validation/comparison_sequential_sets.nf.test"
    [qmri_megre]="test/validation/comparison_sequential_sets.nf.test"
    [qmri_mese]="test/validation/comparison_sequential_sets.nf.test"
    [qmri_mp2rage]="test/validation/comparison_sequential_sets.nf.test"
    [qmri_sa2rage]="test/validation/comparison_sequential_sets.nf.test"
    [qmri_mpm]="test/validation/comparison_mixed_sets.nf.test"
)

CUSTOM_SUITES=(
    "test/validation/comparison_custom_datasets.nf.test"
    "test/validation/test_flattened_output.nf.test"
    "test/validation/test_heterogeneous_suffix_mapping.nf.test"
)

BIDS_SUITES=(
    "test/validation/comparison_plain_sets.nf.test"
    "test/validation/comparison_named_sets.nf.test"
    "test/validation/comparison_sequential_sets.nf.test"
    "test/validation/comparison_mixed_sets.nf.test"
)

EXTRA_SUITES=(
    "test/validation/test_bidsignore.nf.test"
    "test/validation/test_path_types.nf.test"
    "test/validation/test_process_path_input.nf.test"
    "test/validation/test_grouptupleby.nf.test"
    "test/validation/test_joinby.nf.test"
    "test/validation/test_combineby.nf.test"
)

if [[ "${LIST_ONLY}" == true ]]; then
    echo "Custom datasets:"
    printf '  %s\n' ds-dwi ds-dwi2 ds-dwi3 ds-dwi4 ds-mrs_fmrs ds-mtsat
    echo
    echo "BIDS examples datasets:"
    printf '  %s\n' asl001 asl002 eeg_cbm qmri_mtsat qmri_tb1tfl qmri_vfa qmri_irt1 qmri_megre qmri_mese qmri_mp2rage qmri_sa2rage qmri_mpm
    echo
    echo "Suite mapping:"
    for ds in "${!DATASET_TO_SUITE[@]}"; do
        echo "  ${ds} -> ${DATASET_TO_SUITE[$ds]}"
    done | sort
    exit 0
fi

bootstrap_runtime
resolve_nf_test_cmd

TEST_PATHS=()
declare -A SUITE_SEEN=()

add_suite_once() {
    local suite="$1"
    if [[ -z "${SUITE_SEEN[$suite]:-}" ]]; then
        SUITE_SEEN[$suite]=1
        TEST_PATHS+=("$suite")
    fi
}

if [[ ${#SPECIFIC_DATASETS[@]} -gt 0 ]]; then
    for dataset in "${SPECIFIC_DATASETS[@]}"; do
        suite="${DATASET_TO_SUITE[$dataset]:-}"
        if [[ -z "${suite}" ]]; then
            echo "Unknown dataset: ${dataset}"
            echo "Use --list to see supported dataset names."
            exit 1
        fi
        add_suite_once "${suite}"
    done
else
    if [[ "${CUSTOM_ONLY}" == true ]]; then
        for suite in "${CUSTOM_SUITES[@]}"; do
            add_suite_once "${suite}"
        done
    elif [[ "${BIDS_ONLY}" == true ]]; then
        for suite in "${BIDS_SUITES[@]}"; do
            add_suite_once "${suite}"
        done
    else
        for suite in "${CUSTOM_SUITES[@]}" "${BIDS_SUITES[@]}" "${EXTRA_SUITES[@]}"; do
            add_suite_once "${suite}"
        done
    fi
fi

cd "${REPO_ROOT}"

CMD=("${NF_TEST_CMD[@]}" test -c nf-test.config)
if [[ "${VERBOSE}" == true ]]; then
    CMD+=(--verbose)
fi
if [[ "${UPDATE_SNAPSHOTS}" == true ]]; then
    CMD+=(--update-snapshot)
fi
if [[ "${CLEAN_SNAPSHOTS}" == true ]]; then
    CMD+=(--clean-snapshot)
fi
if [[ "${CI_MODE}" == true ]]; then
    CMD+=(--ci)
fi
if [[ "${DRY_RUN}" == true ]]; then
    CMD+=(--dry-run)
fi
CMD+=("${TEST_PATHS[@]}")

echo "Running validation via nf-test"
echo "Suites:"
printf '  %s\n' "${TEST_PATHS[@]}"
echo

"${CMD[@]}"
