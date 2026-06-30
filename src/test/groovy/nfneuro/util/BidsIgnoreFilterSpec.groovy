/* groovylint-disable all */
package nfneuro.plugin.util

import spock.lang.Specification
import spock.lang.TempDir

import java.nio.file.Path

class BidsIgnoreFilterSpec extends Specification {

    @TempDir
    Path tmp

    // -----------------------------------------------------------------------
    // fromBidsRoot / fromFile construction
    // -----------------------------------------------------------------------

    def 'fromBidsRoot returns empty filter when no .bidsignore exists'() {
        expect:
        BidsIgnoreFilter.fromBidsRoot(tmp.toAbsolutePath().toString()).isEmpty()
    }

    def 'fromFile returns empty filter when file does not exist'() {
        expect:
        BidsIgnoreFilter.fromFile('/nonexistent/.bidsignore', tmp.toAbsolutePath().toString()).isEmpty()
    }

    def 'fromBidsRoot loads patterns from .bidsignore in dataset root'() {
        given:
        new File(tmp.toFile(), '.bidsignore').text = 'sub-99/**\n'

        when:
        def filter = BidsIgnoreFilter.fromBidsRoot(tmp.toAbsolutePath().toString())

        then:
        !filter.isEmpty()
    }

    def 'blank lines and comment lines are ignored'() {
        given:
        new File(tmp.toFile(), '.bidsignore').text = '# this is a comment\n\nsub-99/**\n\n'

        when:
        def filter = BidsIgnoreFilter.fromBidsRoot(tmp.toAbsolutePath().toString())
        def ignored = filter.shouldIgnore(tmp.resolve('sub-99/anat/sub-99_T1w.nii.gz').toString())

        then:
        ignored
    }

    // -----------------------------------------------------------------------
    // shouldIgnore — relative paths
    // -----------------------------------------------------------------------

    def 'shouldIgnore matches a simple filename pattern against relative path'() {
        given:
        def filter = new BidsIgnoreFilter(['**/*.json'], tmp.toAbsolutePath().toString())

        expect:
        filter.shouldIgnore('anat/sub-01_T1w.json')
        !filter.shouldIgnore('anat/sub-01_T1w.nii.gz')
    }

    def 'shouldIgnore matches a subject-level wildcard pattern'() {
        given:
        def filter = new BidsIgnoreFilter(['sub-99/**'], tmp.toAbsolutePath().toString())

        expect:
        filter.shouldIgnore('sub-99/anat/sub-99_T1w.nii.gz')
        !filter.shouldIgnore('sub-01/anat/sub-01_T1w.nii.gz')
    }

    // -----------------------------------------------------------------------
    // shouldIgnore — absolute paths
    // -----------------------------------------------------------------------

    def 'shouldIgnore matches absolute path by relativizing against bidsRoot'() {
        given:
        def root = tmp.toAbsolutePath().toString()
        def filter = new BidsIgnoreFilter(['sub-99/**'], root)
        def absPath = tmp.resolve('sub-99/anat/sub-99_T1w.nii.gz').toAbsolutePath().toString()

        expect:
        filter.shouldIgnore(absPath)
    }

    def 'shouldIgnore does not match absolute path outside bidsRoot'() {
        given:
        def root = tmp.toAbsolutePath().toString()
        def filter = new BidsIgnoreFilter(['sub-99/**'], root)
        // Use a different root entirely
        def absPath = '/completely/different/root/sub-99/anat/sub-99_T1w.nii.gz'

        expect:
        !filter.shouldIgnore(absPath)
    }

    // -----------------------------------------------------------------------
    // Multiple patterns
    // -----------------------------------------------------------------------

    def 'shouldIgnore returns true when any pattern matches'() {
        given:
        def filter = new BidsIgnoreFilter(['sub-98/**', 'sub-99/**'], tmp.toAbsolutePath().toString())

        expect:
        filter.shouldIgnore('sub-98/anat/sub-98_T1w.nii.gz')
        filter.shouldIgnore('sub-99/anat/sub-99_T1w.nii.gz')
        !filter.shouldIgnore('sub-01/anat/sub-01_T1w.nii.gz')
    }

    // -----------------------------------------------------------------------
    // Empty filter
    // -----------------------------------------------------------------------

    def 'empty filter never ignores any file'() {
        given:
        def filter = new BidsIgnoreFilter([], tmp.toAbsolutePath().toString())

        expect:
        !filter.shouldIgnore('sub-01/anat/sub-01_T1w.nii.gz')
        !filter.shouldIgnore('/absolute/path/to/file.nii.gz')
        filter.isEmpty()
    }

    // -----------------------------------------------------------------------
    // fromFile with explicit path
    // -----------------------------------------------------------------------

    def 'fromFile loads patterns from a file at an explicit path'() {
        given:
        File ignoreFile = new File(tmp.toFile(), 'custom.bidsignore')
        ignoreFile.text = 'sub-42/**\n'

        when:
        def filter = BidsIgnoreFilter.fromFile(ignoreFile.absolutePath, tmp.toAbsolutePath().toString())

        then:
        filter.shouldIgnore('sub-42/anat/sub-42_T1w.nii.gz')
        !filter.shouldIgnore('sub-01/anat/sub-01_T1w.nii.gz')
    }

}
