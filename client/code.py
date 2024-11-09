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
import alarm
import watchdog
import supervisor
import adafruit_hashlib

# noinspection PyBroadException
try:
	from typing import Optional, Final
except:
	pass

supervisor.runtime.autoreload = False

class Renderer:
	MAX_WAKE_PINS: Final[int] = 1
	BUTTON_MAP: Final[dict[str, int]] = {
		"A": board.D11,
		"B": board.D12,
		"C": board.D13
	}

	def __init__(self):
		self.battery_percent = None
		self.refresh_interval = None

	@staticmethod
	def connect():
		print("Connecting to Wi-Fi...")
		wifi.radio.connect(os.getenv("CIRCUITPY_WIFI_SSID"), os.getenv("CIRCUITPY_WIFI_PASSWORD"))
		print(f"Connected ({wifi.radio.ipv4_address})")

	def build_pin_alarms(self):
		alarms = []
		button_count = 0
		for button in self.BUTTON_MAP:
			button_count = button_count + 1
			if self.MAX_WAKE_PINS is not None and button_count > self.MAX_WAKE_PINS:
				print(f"Ignoring other buttons; too many wake pins")
				break

			pin = self.BUTTON_MAP[button]
			print(f"Setting pin alarm for button {button} on pin {pin}")
			# noinspection PyUnresolvedReferences
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
			# noinspection PyUnresolvedReferences
			alarms.append(alarm.time.TimeAlarm(monotonic_time = monotonic_time))

		print("Entering deep sleep")
		print(f"Total alarms: {len(alarms)}")
		print(alarms)
		alarm.exit_and_deep_sleep_until_alarms(*alarms)
		print("Got past deep sleep, somehow")

	def get_battery_percent(self):
		if self.battery_percent is None:
			attempts = 0
			while True:
				attempts += 1
				# noinspection PyBroadException
				try:
					from adafruit_lc709203f import LC709203F, PackSize
					monitor = LC709203F(board.I2C())
					# noinspection PyUnresolvedReferences
					monitor.pack_size = PackSize.MAH500

					self.battery_percent = int(monitor.cell_percent)
					break
				except Exception as e:
					if attempts >= 5:
						print("Failed to get battery percent")
						import traceback
						traceback.print_exception(e)
						break

					time.sleep(1)

		return self.battery_percent

	@staticmethod
	def get_mac_id():
		mac_id = ""
		for i in wifi.radio.mac_address:
			mac_id += "%x" % i
		return mac_id

	def build_url(self):
		mac_id = self.get_mac_id()
		base_url = os.getenv("IMAGE_SERVER_BASE_URL")
		url = base_url + mac_id + "?"

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

	@staticmethod
	def get_image_bytes(response: adafruit_requests.Response):
		expected_bytes = int(response.headers["content-length"]) if "content-length" in response.headers else None
		total_bytes = 0
		buffer = io.BytesIO()
		for chunk in response.iter_content(chunk_size = 1024):
			# noinspection PyTypeChecker
			total_bytes += len(chunk)
			print(f"Read {total_bytes} of {expected_bytes} bytes")
			# noinspection PyTypeChecker
			buffer.write(chunk)

		buffer.seek(0)
		return buffer

	@staticmethod
	def get_nullable_header(response: adafruit_requests.Response, header: str):
		return response.headers[header] if header in response.headers else None

	@staticmethod
	def get_last_rendered_etag_hash(zero_is_none: bool = True) -> Optional[bytearray]:
		buffer = microcontroller.nvm[0:20]
		if zero_is_none:
			is_empty = True
			for i in range(0, len(buffer)):
				if buffer[i] != 0x0:
					return buffer

			if is_empty:
				return None

		return buffer

	@staticmethod
	def set_last_rendered_etag(etag: Optional[str]):
		if etag is None:
			buffer = bytearray([0x0] * 20)
		else:
			buffer = bytearray.fromhex(adafruit_hashlib.sha1(etag).hexdigest())
		microcontroller.nvm[0:20] = buffer

	def get_last_pressed_button(self):
		# noinspection PyUnresolvedReferences
		if isinstance(alarm.wake_alarm, alarm.pin.PinAlarm):
			print("Explicitly woken up by pin alarm")

			for button in self.BUTTON_MAP:
				if self.BUTTON_MAP[button] == alarm.wake_alarm.pin:
					return button

			print(f"Woken up by pin alarm for pin {alarm.wake_alarm.pin} but not defined in button map")
		else: # either not defined or woken up by timeout; try to get from NVM
			print("Woken up by something other than pin alarm")
			return None

	def persist_etag(self, etag: Optional[str]):
		print(f"Persisting etag {etag}")
		self.set_last_rendered_etag(etag)

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
		# noinspection PyTypeChecker
		requests = adafruit_requests.Session(pool, context)

		url = self.build_url()
		print(f"Sending request to {url}")
		response = requests.get(url, timeout = 10)
		print("Got response with headers:")
		print(response.headers)

		if response.headers["content-type"] != "image/bmp":
			raise ValueError(f"Expected image/bmp Content-Type but got {response.headers['content-type']}")

		return response

	def has_etag_changed(self, response: adafruit_requests.Response):
		etag = self.get_etag(response)
		last_rendered_etag = self.get_last_rendered_etag_hash()

		if etag is None:
			print("No etag in payload")
			return True, etag
		elif last_rendered_etag is None:
			print("No persisted etag")
			return True, etag
		elif bytearray.fromhex(adafruit_hashlib.sha1(etag).hexdigest()) != last_rendered_etag:
			print(f"Etag has changed: was {last_rendered_etag}, is now {etag}")
			return True, etag
		else:
			assert(etag == last_rendered_etag, f"{etag} == {last_rendered_etag}")
			return False, etag

	@staticmethod
	def init_display():
		displayio.release_displays()
		spi = board.SPI()
		epd_cs = board.D9
		epd_dc = board.D10
		epd_reset = None
		epd_busy = None

		# noinspection PyUnresolvedReferences
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

	@staticmethod
	def disconnect():
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
				except Exception as e:
					print(f"Failed making request, retrying: {e}")

			has_etag_changed, etag = self.has_etag_changed(response)
			if has_etag_changed:
				if etag is not None:
					self.persist_etag(etag)
				print("Rendering")
				self.render_response(display, response)
				print("Done rendering")
			else:
				print(f"Not rendering; etag hasn't changed ({etag})")

			self.disconnect()

			refresh_interval = self.get_refresh_interval(response)
			print(f"Refresh interval: {refresh_interval}")

		self.deep_sleep(15 * 60 if refresh_interval is None else refresh_interval)

	@staticmethod
	def render_bitmap(display, bitmap, palette):
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
			# noinspection PyTypeChecker
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

renderer = Renderer()
renderer.get_and_render()
