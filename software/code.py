import ipaddress
import ssl
import wifi
import socketpool
import adafruit_requests
import board
import os
import io
import displayio
import adafruit_imageload
import time
import adafruit_il0373
import microcontroller
import binascii
import alarm
import watchdog
import adafruit_uc8151d
import supervisor

supervisor.runtime.autoreload = False

NVM_OFFSETS = {
	"etag": {
		"start": 0,
		"length": 20
	},
	"wake_button": {
		"start": 20,
		"length": 1
	}
}

FORCE_RENDER = True

class MagTagRenderer:
	def __init__(self):
		self.refresh_interval = None

	def get_button_map(self):
		raise NotImplementedError()

	def get_max_wake_pins(self):
		return None

	def connect(self):
		print("Connecting to Wi-Fi...")
		wifi.radio.connect(os.getenv("CIRCUITPY_WIFI_SSID"), os.getenv("CIRCUITPY_WIFI_PASSWORD"))
		print(f"Connected ({wifi.radio.ipv4_address})")

	def build_pin_alarms(self):
		alarms = []
		button_count = 0
		max_wake_pins = self.get_max_wake_pins()
		button_map = self.get_button_map()
		for button in button_map:
			button_count = button_count + 1
			if max_wake_pins is not None and button_count > max_wake_pins:
				print(f"Ignoring other buttons; too many wake pins")
				break

			pin = button_map[button]
			print(f"Setting pin alarm for button {button} on pin {pin}")
			alarms.append(alarm.pin.PinAlarm(pin = pin, value = False, pull = True))

		print(f"Waking on {len(alarms)} pin alarms")

		return alarms

	def deep_sleep(self, seconds: int):
		if seconds == 0:
			seconds = None
		else:
			assert(seconds > 0)
			if seconds < 300:
				print(f"Sleep request was for {seconds} seconds but forcing 300 seconds for display safety")
				seconds = 300

		alarms = self.build_pin_alarms()

		if seconds is not None:
			monotonic_time = time.monotonic() + seconds
			print(f"Setting time alarm for {monotonic_time} seconds monotonic ({seconds} seconds from now)")
			alarms.append(alarm.time.TimeAlarm(monotonic_time = monotonic_time))

		print("Entering deep sleep")
		print(f"Total alarms: {len(alarms)}")
		print(alarms)
		alarm.exit_and_deep_sleep_until_alarms(*alarms)
		print("Got past deep sleep, somehow")

	def get_battery_percent(self):
		return None # likely overridden by a subclass, but some devices might not know

	def get_mac_id(self):
		mac_id = ""
		for i in wifi.radio.mac_address:
			mac_id += "%x" % i
		return mac_id

	def build_url(self):
		mac_id = self.get_mac_id()
		base_url = os.getenv("IMAGE_SERVER_BASE_URL")
		url = base_url + mac_id

		battery = self.get_battery_percent()
		if battery is not None:
			if battery < 0 or battery > 100:
				print(f"Battery percent is {battery}% which isn't plausible; normalizing it to 0% to 100%")
				battery = min(100, max(battery, 0))
			url += f"&battery_percent={battery}"

		button = self.get_last_pressed_button()
		if button is not None:
			url += f"&button={button}"

		return url

	def get_image_bytes(self, response: adafruit_requests.Response):
		buffer = io.BytesIO()
		expected_bytes = int(response.headers["content-length"]) if "content-length" in response.headers else None

		print(f"Reading response, expecting {expected_bytes} bytes")
		payload = response.content
		total_bytes_read = len(payload)
		print(f"Got {total_bytes_read} bytes")

		socket = response.socket
		chunk = bytearray(1024)
		print("Reading first chunk")
		bytes_read = socket.recv_into(chunk)
		print(f"Got {bytes_read} bytes")
		total_bytes_read = 0
		while bytes_read > 0:
			total_bytes_read += bytes_read
			print(f"Read {total_bytes_read} of {expected_bytes} bytes")
			bytes_read = socket.recv_into(chunk)

		print(len(chunk))

		return chunk

		buffer.seek(0)
		return buffer

	def get_nullable_header(self, response: adafruit_requests.Response, header: str):
		return response.headers[header] if header in response.headers else None

	def get_nvm_offsets(self, key):
		if key not in NVM_OFFSETS:
			raise Exception(f"Unknown NVM offset {key}")

		return NVM_OFFSETS[key]["start"], NVM_OFFSETS[key]["start"] + NVM_OFFSETS[key]["length"]

	def nvm_get(self, key, zero_is_none: bool = True):
		start_index, end_index = self.get_nvm_offsets(key)

		buffer = microcontroller.nvm[start_index:end_index]
		assert(len(buffer) == NVM_OFFSETS[key]["length"])
		if zero_is_none:
			is_empty = True
			for i in range(0, len(buffer)):
				if buffer[i] != 0x0:
					return buffer

			if is_empty:
				return None

		return buffer

	def nvm_set(self, key, buffer: bytes):
		start_index, end_index = self.get_nvm_offsets(key)

		if buffer is None:
			print("Coercing NVM buffer to an empty byte array")
			buffer = 0x0 * NVM_OFFSETS[key]["length"]

		assert(len(buffer) == NVM_OFFSETS[key]["length"])

		microcontroller.nvm[start_index:end_index] = buffer

	def get_last_rendered_etag(self):
		etag = self.nvm_get("etag")
		if etag is not None:
			etag = binascii.hexlify(etag).decode("ascii")

		return etag

	def get_last_pressed_button(self):
		button_map = self.get_button_map()
		if isinstance(alarm.wake_alarm, alarm.pin.PinAlarm):
			print("Explicitly woken up by pin alarm")

			for button in button_map:
				if button_map[button] == alarm.wake_alarm.pin:
					return button

			print(f"Woken up by pin alarm for pin {alarm.wake_alarm.pin} but not defined in button map")
		else: # either not defined or woken up by timeout; try to get from NVM
			print("Woken up by something other than pin alarm; checking NVM for last wake button")
			wake_button = self.nvm_get("wake_button")
			if wake_button is not None:
				wake_button = wake_button.decode("ascii")
				if wake_button not in button_map:
					print(f"NVM references button {wake_button} as the wake button but isn't defined in button map")
					return None

				print(f"Last wake button was {wake_button}")
				return wake_button

			print(f"No wake button in NVM")
			return None

	def persist_etag(self, etag: str):
		if etag is None:
			etag = "0000000000000000000000000000000000000000"
		print(f"Persisting etag {etag}")
		self.nvm_set("etag", binascii.unhexlify(etag))

	def get_etag(self, response: adafruit_requests.Response):
		return self.get_nullable_header(response, "etag")

	def get_refresh_interval(self, response: adafruit_requests.Response):
		refresh_interval = self.get_nullable_header(response, "x-refresh-in")
		if refresh_interval is not None:
			refresh_interval = int(refresh_interval)

		return refresh_interval

	def make_request(self):
		context = ssl.create_default_context()
		pool = socketpool.SocketPool(wifi.radio)
		requests = adafruit_requests.Session(pool, context)

		url = self.build_url()
		print(f"Sending request to {url}")
		response = requests.get(url, timeout = 10)
		print("Got response with headers:")
		print(response.headers)
		return response

	def has_etag_changed(self, response: adafruit_request.Response):
		global FORCE_RENDER
		if FORCE_RENDER:
			print(f"Pretending ETag changed to force render")
			return True, None

		etag = self.get_etag(response)
		last_rendered_etag = self.get_last_rendered_etag()

		if etag is None:
			print("No etag in payload")
			return True, etag
		elif last_rendered_etag is None:
			print("No persisted etag")
			return True, etag
		elif etag != last_rendered_etag:
			print(f"Etag has changed: was {last_rendered_etag}, is now {etag}")
			return True, etag
		else:
			assert(etag == last_rendered_etag)
			return False, etag

	def init_display(self):
		raise NotImplementedError()

	def render(self, display, response: adafruit_requests.Response):
		raise NotImplementedError()

	def disconnect(self):
		wifi.radio.enabled = False

	def get_and_render(self):
		refresh_interval = None

		display = self.init_display()

		battery_percent = self.get_battery_percent()
		if battery_percent is not None and battery_percent <= 5:
			self.persist_etag(None)
			self.render_low_battery(display)
		else:
			response = None

			while response is None:
				try:
					self.connect()
					response = self.make_request()
					self.disconnect()
				except Exception as e:
					print(f"Failed making request: {e}")

			has_etag_changed, etag = self.has_etag_changed(response)
			if has_etag_changed:
				if etag is not None:
					self.persist_etag(etag)
				print("Rendering")
				self.render_response(display, response)
				print("Done rendering")
			else:
				print(f"Not rendering; etag hasn't changed ({etag}")

			refresh_interval = self.get_refresh_interval(response)
			print(f"Refresh interval: {refresh_interval}")

		self.deep_sleep(15 * 60 if refresh_interval is None else refresh_interval)

class AdafruitFeatherESP32S2MagTagRenderer(MagTagRenderer):
	def __init__(self):
		self.battery_percent = None

	def get_battery_percent(self):
		if self.battery_percent is None:
			try:
				from adafruit_lc709203f import LC709203F, PackSize
				monitor = LC709203F(board.I2C())
				monitor.pack_size = PackSize.MAH500

				self.battery_percent = int(monitor.cell_percent)
			except:
				print("Exception connecting to LC709203F; trying MAX17048 instead")
				import adafruit_max1704x
				self.battery_percent = int(adafruit_max1704x.MAX17048(board.I2C()).cell_percent)

		return self.battery_percent

	def get_button_map(self):
		return {
			"A": board.D11,
			"B": board.D12,
			"C": board.D13
		}

	def get_max_wake_pins(self):
		return 1

	def init_display(self):
		displayio.release_displays()
		spi = board.SPI()
		epd_cs = board.D9
		epd_dc = board.D10
		epd_reset = None
		epd_busy = None

		display_bus = displayio.FourWire(
			spi, command = epd_dc, chip_select = epd_cs, reset = epd_reset, baudrate = 1000000
		)

		time.sleep(1)

		display = adafruit_il0373.IL0373(
			display_bus,
			width = 296,
			height = 128,
			rotation = 270,
			busy_pin = epd_busy,
			highlight_color = 0xFF0000,
		)

		return display

	def render_bitmap(self, display, bitmap, palette):
		group = displayio.Group()
		group.append(displayio.TileGrid(bitmap, pixel_shader = palette))
		display.root_group = group

		display.refresh()

	def render_low_battery(self, display):
		bitmap, palette = adafruit_imageload.load("low-battery.bmp")
		self.render_bitmap(display, bitmap, palette)

	def render_response(self, display, response: adafruit_requests.Response):
		try:
			print("Filling buffer")
			buffer = self.get_image_bytes(response)
			print("Loading from buffer")
			bitmap, palette = adafruit_imageload.load(buffer)
			print("Rendering bitmap")
			self.render_bitmap(display, bitmap, palette)
		except Exception as e:
			print(f"Render failed: {e}")
			import traceback
			traceback.print_exception(e)
			self.persist_etag(None)

microcontroller.watchdog.timeout = 60
microcontroller.watchdog.mode = watchdog.WatchDogMode.RESET
microcontroller.watchdog.feed()

BOARD_CLASSES = {
	"adafruit_feather_esp32s2": AdafruitFeatherESP32S2MagTagRenderer
}

if board.board_id not in BOARD_CLASSES:
	raise NotImplementedError(f"Board {board.board_id} not defined in BOARD_CLASSES")

klass = BOARD_CLASSES[board.board_id]
print(f"Using {klass}")
renderer = klass()
renderer.get_and_render()
