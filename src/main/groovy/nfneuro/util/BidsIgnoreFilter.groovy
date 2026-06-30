package nfneuro.plugin.util

import groovy.transform.CompileStatic
import java.nio.file.FileSystems
import java.nio.file.Path
import java.nio.file.PathMatcher
import java.nio.file.Paths

/**
 * Parses a {@code .bidsignore}-style file and tests whether a given file path
 * should be excluded from a BIDS dataset.
 *
 * <p>The file format follows the same conventions as {@code .gitignore}:
 * one glob pattern per line, blank lines and lines starting with {@code #}
 * are ignored.  Patterns are matched against the path of each file
 * relative to the BIDS dataset root.</p>
 *
 * <p>Glob syntax is handled by {@link java.nio.file.FileSystems} with the
 * {@code glob:} scheme, which supports {@code *}, {@code **}, {@code ?},
 * and character classes.</p>
 *
 * <h3>Usage</h3>
 * <pre>
 * def filter = BidsIgnoreFilter.fromFile('/data/bids/.bidsignore', '/data/bids')
 * bidsFiles.removeAll { file -> filter.shouldIgnore(file.path) }
 * </pre>
 */
@CompileStatic
class BidsIgnoreFilter {

    private final List<PathMatcher> matchers
    private final String bidsRoot

    /**
     * Construct a filter from an explicit list of glob patterns.
     *
     * @param patterns list of glob patterns (may be empty)
     * @param bidsRoot absolute path to the BIDS dataset root, used to compute
     *                 relative paths when matching
     */
    BidsIgnoreFilter(List<String> patterns, String bidsRoot) {
        this.bidsRoot = bidsRoot
        List<PathMatcher> built = []
        patterns.each { String pattern ->
            built << FileSystems.getDefault().getPathMatcher("glob:${pattern}")
        }
        this.matchers = built
    }

    /**
     * Create a filter by reading a bidsignore file.
     *
     * <p>If the file does not exist an empty (no-op) filter is returned.</p>
     *
     * @param ignoreFilePath absolute path to the bidsignore file
     * @param bidsRoot       absolute path to the BIDS dataset root
     * @return a configured {@code BidsIgnoreFilter}
     */
    static BidsIgnoreFilter fromFile(String ignoreFilePath, String bidsRoot) {
        File ignoreFile = new File(ignoreFilePath)
        if (!ignoreFile.exists() || !ignoreFile.isFile()) {
            return new BidsIgnoreFilter([], bidsRoot)
        }
        List<String> patterns = []
        ignoreFile.readLines().each { String line ->
            String trimmed = line.trim()
            if (trimmed && !trimmed.startsWith('#')) {
                patterns << trimmed
            }
        }
        return new BidsIgnoreFilter(patterns, bidsRoot)
    }

    /**
     * Create a filter by auto-detecting {@code .bidsignore} at the dataset root.
     *
     * @param bidsRoot absolute path to the BIDS dataset root
     * @return a configured {@code BidsIgnoreFilter}
     */
    static BidsIgnoreFilter fromBidsRoot(String bidsRoot) {
        return fromFile(new File(bidsRoot, '.bidsignore').absolutePath, bidsRoot)
    }

    /**
     * Test whether a file path should be ignored.
     *
     * <p>The path is first made relative to {@link #bidsRoot} so that patterns
     * such as {@code sub-xx/anat/**} work correctly regardless of whether
     * absolute or relative paths are supplied.</p>
     *
     * @param filePath absolute or relative path to the file under test
     * @return {@code true} if at least one pattern matches and the file should
     *         be discarded; {@code false} to keep the file
     */
    boolean shouldIgnore(String filePath) {
        if (matchers.isEmpty()) {
            return false
        }
        Path relative = relativize(filePath)
        for (PathMatcher matcher : matchers) {
            if (matcher.matches(relative)) {
                return true
            }
        }
        return false
    }

    /**
     * Return {@code true} if the filter carries no patterns (i.e. it is a no-op).
     *
     * @return {@code true} when no patterns were loaded
     */
    boolean isEmpty() {
        return matchers.isEmpty()
    }

    // --- private helpers ---------------------------------------------------

    private Path relativize(String filePath) {
        Path path = Paths.get(filePath)
        if (!path.isAbsolute()) {
            return path
        }
        Path root = Paths.get(bidsRoot).toAbsolutePath()
        try {
            return root.relativize(path.toAbsolutePath())
        } catch (IllegalArgumentException ignored) {
            // If relativization fails (e.g. different filesystem roots), use
            // the filename only so simple patterns still work.
            return path.getFileName()
        }
    }

}
