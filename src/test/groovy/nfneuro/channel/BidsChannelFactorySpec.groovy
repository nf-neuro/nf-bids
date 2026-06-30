/* groovylint-disable all */
package nfneuro.plugin.channel

import nextflow.Session
import spock.lang.Specification
import spock.lang.TempDir

import java.nio.file.Path

/**
 * Unit tests for BidsChannelFactory pre-flight validation.
 */
class BidsChannelFactorySpec extends Specification {

    @TempDir
    Path tmp

    BidsChannelFactory factory

    def setup() {
        factory = new BidsChannelFactory(Mock(Session))
    }

    // Helper: invoke private preFlightChecks via reflection and unwrap any
    // InvocationTargetException so that Spock's thrown() works normally.
    private void callPreFlightChecks(String bidsDir, String configPath, Map options) {
        def method = BidsChannelFactory.getDeclaredMethod('preFlightChecks', String, String, Map)
        method.setAccessible(true)
        try {
            method.invoke(factory, bidsDir, configPath, options)
        } catch (java.lang.reflect.InvocationTargetException e) {
            throw e.cause
        }
    }

    // -----------------------------------------------------------------------
    // options.bidsignore validation
    // -----------------------------------------------------------------------

    def 'preFlightChecks throws when options.bidsignore path does not exist'() {
        given:
        def nonExistentPath = tmp.resolve('no-such.bidsignore').toString()

        when:
        callPreFlightChecks(tmp.toString(), null, [bidsignore: nonExistentPath])

        then:
        def e = thrown(IllegalArgumentException)
        e.message.contains('Bidsignore file not found')
    }

    def 'preFlightChecks passes when options.bidsignore points to an existing file'() {
        given:
        def ignoreFile = tmp.resolve('.bidsignore').toFile()
        ignoreFile.text = 'sub-phantom/**\n'

        when:
        callPreFlightChecks(tmp.toString(), null, [bidsignore: ignoreFile.absolutePath])

        then:
        noExceptionThrown()
    }

    def 'preFlightChecks passes when options.bidsignore is absent from the options map'() {
        when:
        callPreFlightChecks(tmp.toString(), null, [:])

        then:
        noExceptionThrown()
    }

}
