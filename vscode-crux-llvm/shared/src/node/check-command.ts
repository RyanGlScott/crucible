/**
 * NOTE: You *CANNOT* import this file from the webview, as it uses Node's
 * 'child_process', which is not available in webviews.
 *
 * If you need to perform such commands for the webview, have it communicate to
 * the extension client, and have the client do the work.
 * */

import * as ChildProcess from 'child_process'

import { CheckCommandResult } from '../check-command-result'
import { Configuration } from '../configuration'
import { settingsName } from '../constants'

/**
 * Tries to run the given command with the '--version' flag to check for its
 * existence.
 *
 * @param configuration - crux-llvm fragment of the user's settings.json
 *
 * @param commandStr - one of the command names expected as fields (see
 * vscode-crux-llvm/package.json) for an up-to-date list
 *
 * @returns true when command can be found, false otherwise
 */
export function checkCommand<
    Key extends keyof Configuration,
    SubConfiguration extends Configuration & Record<Key, string>
>(
    configuration: Configuration,
    commandStr: Key,
): CheckCommandResult {
    try {
        const output = ChildProcess.execFileSync(
            (configuration as SubConfiguration)[commandStr],
            ['--version'],
        )
        return {
            check: true,
            output: output.toString(),
        }
    } catch (e) { // ! e will be null
        return {
            check: false,
            errorMessage: `${commandStr} could not be found.  Please set or update "${settingsName}.${commandStr}" correctly in your settings.json.\n${e}`,
        }
    }
}

/**
 * Checks that we can access a given command using the user's settings PATH.
 *
 * @param configuration - crux-llvm fragment of the user's settings.json
 * @param commandStr - a verbatim command name we expect to found in PATH
 * @returns true when command can be found, false otherwise
 */
export function checkCommandViaPATH(
    configuration: Configuration,
    commandStr: string,
): CheckCommandResult {
    try {
        const output = ChildProcess.execFileSync(
            commandStr,
            ['--version'],
            {
                env: {
                    PATH: configuration['path'],
                },
            },
        )
        return {
            check: true,
            output: output.toString(),
        }
    } catch (e) {
        return {
            check: false,
            errorMessage: `${commandStr} could not be found.  Please make sure that "${settingsName}.path" is a PATH containing ${commandStr} in your settings.json.\n${e}`,
        }
    }
}
