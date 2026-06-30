package nfneuro.plugin.channel

import groovy.transform.CompileStatic
import groovy.util.logging.Slf4j
import nextflow.Channel
import nextflow.Session
import nextflow.plugin.extension.Factory
import nfneuro.plugin.parser.BidsParser
import nfneuro.plugin.util.BidsLogger
import groovyx.gpars.dataflow.DataflowWriteChannel
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.Files

/**
 * Channel factory for creating BIDS-structured Nextflow channels.
 *
 * <p>Orchestrates the full {@code Channel.fromBIDS()} workflow: pre-flight validation,
 * invocation of {@link nfneuro.plugin.parser.BidsParser} via libBIDS.sh, configuration
 * loading, routing to the appropriate {@link nfneuro.plugin.grouping.BaseSetHandler}
 * sub-class, and emission of structured BIDS data onto a Dataflow channel.</p>
 *
 * <p>The main entry point is {@link #fromBIDS(String, String, Map)}, which is called by
 * {@link nfneuro.plugin.BidsExtension}.</p>
 */
@Slf4j
@CompileStatic
class BidsChannelFactory {

    private final Session session

    /**
     * Construct a new factory bound to the given Nextflow session.
     *
     * @param session the active Nextflow session used for channel creation and ignition
     */
    BidsChannelFactory(Session session) {
        this.session = session
    }

    /**
     * Create a channel from a BIDS dataset
     *
     * Main factory method that implements the complete bids2nf workflow
     *
     * @param bidsDir Path to BIDS dataset directory
     * @param configPath Path to bids2nf YAML configuration (optional)
     * @param options Additional options map (validation, libbids_sh path, entity_aliases_json, etc.)
     * @return DataflowWriteChannel containing structured BIDS data
     *
     * @reference Workflow orchestration:
     *            https://github.com/agahkarakuzu/bids2nf/blob/main/main.nf#L20-L56
     */
    @Factory
    DataflowWriteChannel fromBIDS(String bidsDir, String configPath = null, Map options = [:]) {
        BidsLogger.logProgress("Starting BIDS dataset parsing: ${bidsDir}")

        // Pre-flight checks
        preFlightChecks(bidsDir, configPath, options)

        // BIDS validation (optional)
        // if (options.bids_validation != false) {
        //     validator.validate(bidsDir, options.ignore_codes ?: [99, 36])
        // } else {
        //     BidsLogger.logProgress("nf-bids",
        //         "---------------------------\n" +
        //         "[nf-bids] ⚠︎⚠︎⚠︎ BIDS validation disabled by configuration ⚠︎⚠︎⚠︎\n" +
        //         "[nf-bids] ---------------------------\n")
        // }
        return new BidsHandler()
            .withConfig(configPath)
            .withBidsDir(bidsDir)
            .withOpts(options)
            .withParser(new BidsParser(session))
            .ignite(session)
    }

    /**
     * Perform pre-flight validation checks
     *
     * Validates BIDS directory, configuration file, and libBIDS.sh availability
     *
     * @param bidsDir Path to BIDS dataset
     * @param configPath Path to configuration file
     * @param options Options map
     */
    private void preFlightChecks(String bidsDir, String configPath, Map options) {
        BidsLogger.logProgress('✈︎✈︎✈︎ Pre-flight checks started')

        // Validate BIDS directory exists
        Path bidsPath = Paths.get(bidsDir)
        if (!Files.exists(bidsPath) || !Files.isDirectory(bidsPath)) {
            throw new IllegalArgumentException("BIDS directory does not exist: ${bidsDir}")
        }

        // Validate configuration file if provided
        if (configPath) {
            Path configFile = Paths.get(configPath)
            if (!Files.exists(configFile)) {
                throw new IllegalArgumentException("Configuration file not found: ${configPath}")
            }
        }

        // Validate libBIDS.sh if required
        if (options.libbids_sh) {
            Path libBidsPath = Paths.get(options.libbids_sh as String)
            if (!Files.exists(libBidsPath)) {
                throw new IllegalArgumentException("libBIDS.sh not found: ${options.libbids_sh}")
            }
        }

        if (options.entity_aliases_json) {
            Path aliasesPath = Paths.get(options.entity_aliases_json as String)
            if (!Files.exists(aliasesPath) || !Files.isRegularFile(aliasesPath)) {
                throw new IllegalArgumentException("Entity aliases JSON file not found: ${options.entity_aliases_json}")
            }
        }

        if (options.bidsignore) {
            Path bidsignorePath = Paths.get(options.bidsignore as String)
            if (!Files.exists(bidsignorePath) || !Files.isRegularFile(bidsignorePath)) {
                throw new IllegalArgumentException("Bidsignore file not found: ${options.bidsignore}")
            }
        }

        BidsLogger.logProgress('✓ Pre-flight checks completed')
    }

}
