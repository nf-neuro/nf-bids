#!/usr/bin/env nextflow

/*
 * Test workflow for bidsignore filtering.
 * Validates that files matching patterns in a .bidsignore file are excluded
 * from the channel before grouping.
 */

include { fromBIDS } from "plugin/nf-bids"

params.bids_dir   = params.bids_dir   ?: "${projectDir}/../data/custom/ds-bidsignore"
params.config     = params.config     ?: "${projectDir}/../configs/config_t1w.yaml"
params.bidsignore = params.bidsignore ?: null

/*
 * Workflow exercising auto-detection of .bidsignore at the dataset root.
 */
workflow test_bidsignore_autodetect {
    main:
        def ch = channel.fromBIDS(params.bids_dir, params.config, [:])
    emit:
        bids_channel = ch
}

/*
 * Workflow exercising explicit options.bidsignore override.
 * The caller supplies the path of a custom ignore file via params.bidsignore.
 */
workflow test_bidsignore_explicit {
    main:
        def opts = [bidsignore: params.bidsignore]
        def ch   = channel.fromBIDS(params.bids_dir, params.config, opts)
    emit:
        bids_channel = ch
}

workflow {
    test_bidsignore_autodetect()
    test_bidsignore_autodetect.out.bids_channel.view { item ->
        "bidsignore-autodetect: subject=${item.meta.subject}"
    }
}
