/**
 *  Hunter Douglas Platinum Gateway Shade Control Switch for SmartThings
 *  Attempt to make the shade act like a shade, rather than like a switch
 * Specifically for silohuette shades with vane control 
 *  John Abraham, based on code from Schwark Satyavolu
 *  Originally based on: Allan Klein's (@allanak) and Mike Maxwell's code
 *
 *  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
 *  in compliance with the License. You may obtain a copy of the License at:
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed
 *  on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License
 *  for the specific language governing permissions and limitations under the License.
 *
 */

metadata {
	definition (name: "Platinum Gateway Shade Silhouette", namespace: "schwark", author: "John Abraham") {
	capability "Window Shade"
	capability "Switch Level"
	command "setShadeNo", ["string"]
    command "setVanes", ["number"]
	}

	simulator {
			// TODO: define status and reply messages here
		}

	tiles {
		standardTile("switch", "device.window shade", width: 1, height: 1, canChangeIcon: true) {
				state "closed", label: '${name}', action: "window shade.open", icon: "st.Home.home9", backgroundColor: "#79b821"
				state "open", label: '${name}', action: "window shade.close", icon: "st.Home.home9", backgroundColor: "#ffffff"
			}
		controlTile("levelSliderControl", "device.level", "slider", height: 2, width: 2, inactiveLabel: false) {
			state "level", action:"switch level.setLevel"
		}
		controlTile("mediumSlider", "device.vanes", "slider", height: 1, width: 2, inactiveLabel: false) {
			state "vanes", action:"setVanes"
		}


		main("switch")
		details(["switch", "levelSliderControl", "mediumSlider"])
	}
}

preferences {
}

def installed() {
	log.debug("installed Shade with settings ${settings}")
	initialize()
}

def initialize() {
}

def updated() {
}

def close() {
	return setLevel(0)
}

def open() {
	return setLevel(100)
}

def setLevel(percent) {
	parent.setShadeLevel(state.shadeNo, 100 - percent)
	if(percent == 0) {
		sendEvent(name: "switch", value: "closed")
	} else if (percent == 100) {
		sendEvent(name: "switch", value: "open")
	}
	sendEvent(name: "level", value: percent)
}

def setVanes(percent) {
	log.debug "Setting Vanes on Shade ${shadeNo} to ${percent}%"
	def vaneValue = 255 - (percent * 2.55).toInteger()
	log.debug "Setting Vanes on Shade ${state.shadeNo} to ${vaneValue} value"
	def msg = String.format("\$pss%s-07-%03d",state.shadeNo,vaneValue)
	parent.sendMessage(["msg":msg])
	parent.runIn(1, "sendMessage", [overwrite: false, data:["msg":"\$rls"]])

}


def setShadeNo(shadeNo) {
	state.shadeNo = shadeNo
}