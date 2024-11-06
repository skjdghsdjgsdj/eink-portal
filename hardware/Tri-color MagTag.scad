VIEWABLE_MIN_X = 8.5;
VIEWABLE_WIDTH = 68.5;
VIEWABLE_MIN_Y = 8;
VIEWABLE_DEPTH = 31;

DISPLAY_WIDTH = 79.5;
DISPLAY_DEPTH = 47;
DISPLAY_Z_PROJECTION = 1;

FEATHER_WIDTH = 2 * 25.4;
FEATHER_DEPTH = 22.8;
FEATHER_HEIGHT = 1.6;

HEADER_TOP_PROJECTION = 6;
HEADER_BOTTOM_PROJECTION = 3;
HEADER_RETAINER_DEPTH = 2.6;
HEADER_RETAINER_HEIGHT = 2.5;
HEADER_DIAMETER = 0.6;

FEATHER_X_OFFSET = 28.5;
FEATHER_Y_OFFSET = 12;
FEATHER_Z_OFFSET = -HEADER_RETAINER_HEIGHT - 4.1;
FEATHER_PCB_HEIGHT = 1.4;

CASE_RADIUS = 2;
CASE_EXTRA_WIDTH = 1;
CASE_EXTRA_DEPTH = 0.5;

CASE_HEIGHT = 18.5;
 
function case_inner_width() = DISPLAY_WIDTH + CASE_EXTRA_WIDTH * 2 + abs(viewable_delta_x() * 2);
function case_outer_width() = case_inner_width() + SURFACE * 2;
function case_inner_depth() = DISPLAY_DEPTH + CASE_EXTRA_DEPTH * 2;

function case_outer_min_x() = -CASE_EXTRA_WIDTH - SURFACE;
function case_outer_max_x() = case_outer_width() + case_outer_min_x();

function viewable_delta_x() = VIEWABLE_MIN_X - (DISPLAY_WIDTH / 2 - VIEWABLE_WIDTH / 2);
function viewable_delta_y() = VIEWABLE_MIN_Y - (DISPLAY_DEPTH / 2 - VIEWABLE_DEPTH / 2);

SURFACE = 1.5;

DISPLAY_STANDOFF_X_INSET = 2.6;
DISPLAY_STANDOFF_Y_INSET = 2.4;

USB_C_HOLE_WIDTH = 13;
USB_C_HOLE_Y_DELTA = -0.5;
USB_C_HOLE_Z = FEATHER_Z_OFFSET - 4.8;
USB_C_HOLE_RADIUS = 3.2;
USB_C_EXTRA_DEPTH = 6.3;
USB_C_BRIDGE_EXTRA_WIDTH = 8;

SCREW_HEIGHT = 6.3;
SCREW_HEAD_DIAMETER = 4.3;
SCREW_HEAD_HEIGHT = 2;
SCREW_SHAFT_DIAMETER = 2;

SCREW_X_INSET = 13.5;
SCREW_Y_INSET = 1.5;

BATTERY_WIDTH = 29.6;
BATTERY_DEPTH = 35.7;
BATTERY_HEIGHT = 4.7;

POWER_SWITCH_STANDOFF_HEIGHT = 4;
POWER_SWITCH_Y = 7;
POWER_BUTTON_HOLE_DIAMETER = 7.5;
POWER_BUTTON_SPACING = 18.5;

MAGNET_WIDTH = 29.6;
MAGNET_DEPTH = 9.5;
MAGNET_HEIGHT = 2.7;

MAGNET_X = BATTERY_WIDTH - CASE_EXTRA_WIDTH + 3;
MAGNET_Y_INSET = 1;
MAGNET_BUFFER = 1;
MAGNET_Z_SPACING = 0.8;

// name, X offset, apply to model or not
BUTTONS = [
	["A", 19.65, true],
	["B", 39.65, true],
	["C", 59.65, true]
];

BUTTON_Y_PROJECTION = 4;
BUTTON_Y_INSET = 3.6;
BUTTON_Z = -3.35;

BUTTON_CUTOUT_SIZE = 5;
BUTTON_CUTOUT_SIZE_TOLERANCE = 0.4;

module male_headers(count, pitch = 2.54) {
	assert(count >= 1);
	
	cube([pitch * count, HEADER_RETAINER_DEPTH, HEADER_RETAINER_HEIGHT]);
	for (x = [0 : count - 1]) {
		translate([x * pitch + pitch / 2, HEADER_RETAINER_DEPTH / 2, -HEADER_BOTTOM_PROJECTION])
		cylinder(d = HEADER_DIAMETER, h = HEADER_TOP_PROJECTION + HEADER_RETAINER_HEIGHT + HEADER_BOTTOM_PROJECTION);
	}
}

module display() {
	translate([0, 4.4, 0])
	import("4778 2.9 inch E-Ink Featherwing.stl");
	
	color("blue")
	translate([VIEWABLE_MIN_X, VIEWABLE_MIN_Y, DISPLAY_Z_PROJECTION])
	cube([VIEWABLE_WIDTH, VIEWABLE_DEPTH, 0.1]);
}

module feather() {
	translate([FEATHER_X_OFFSET + FEATHER_WIDTH, FEATHER_Y_OFFSET, FEATHER_Z_OFFSET - FEATHER_HEIGHT])
	rotate([180, 0, 180])
	union() {
		import("5303 Feather ESP32-S2.stl");
		
		translate([5.1, 2.5, 0])
		rotate([180, 0, 0])
		male_headers(16);
		
		translate([15.2, 22.9, 0])
		rotate([180, 0, 0])
		male_headers(12);
	}
}

module shell(size_delta = 0, height = CASE_HEIGHT, z_delta = DISPLAY_Z_PROJECTION) {
	translate([0, 0, size_delta])
	hull() {
		for (x = [
			-CASE_EXTRA_WIDTH + CASE_RADIUS - size_delta,
			DISPLAY_WIDTH + CASE_EXTRA_WIDTH - CASE_RADIUS + size_delta + abs(viewable_delta_x() * 2)
		]) {
			for (y = [
				-CASE_EXTRA_DEPTH + CASE_RADIUS - size_delta,
				DISPLAY_DEPTH + CASE_EXTRA_DEPTH - CASE_RADIUS + size_delta
			]) {
				translate([x, y, -height + z_delta])
				cylinder(r = CASE_RADIUS, h = height, $fn = 36);
			}
		}
	}
}

module usb_c_hole(extra_depth = 0.01) {
	depth = SURFACE + USB_C_EXTRA_DEPTH + extra_depth;

	// USB C hole
	translate([
		case_outer_max_x() - depth + extra_depth / 2,
		case_inner_depth() / 2 + USB_C_HOLE_Y_DELTA,
		USB_C_HOLE_Z
	])
	union() {
		for (y = [-USB_C_HOLE_WIDTH / 2 + USB_C_HOLE_RADIUS, USB_C_HOLE_WIDTH / 2 - USB_C_HOLE_RADIUS]) {
			translate([0, y, 0])
			rotate([90, 0, 90])
			cylinder(r = USB_C_HOLE_RADIUS, h = depth, $fn = 36);
		}
		
		translate([depth / 2, 0, 0])
		cube([depth, USB_C_HOLE_WIDTH - USB_C_HOLE_RADIUS * 2, USB_C_HOLE_RADIUS * 2], center = true);
	}
}

module usb_c_bridge() {
	relative_height = -CASE_HEIGHT + SURFACE + DISPLAY_Z_PROJECTION;
	width = SURFACE + USB_C_EXTRA_DEPTH;
	
	translate([
		case_outer_max_x() - width,
		case_inner_depth() / 2 + USB_C_HOLE_Y_DELTA - USB_C_HOLE_WIDTH / 2 - USB_C_BRIDGE_EXTRA_WIDTH / 2,
		relative_height
	])
	cube([SURFACE + USB_C_EXTRA_DEPTH, USB_C_HOLE_WIDTH + USB_C_BRIDGE_EXTRA_WIDTH, abs(relative_height) - abs(USB_C_HOLE_Z)]);
}

module case() {
	// button guides
	for (button = BUTTONS) {
		if (button[2]) { // visible or not
			x = button[1];
			
			outer_width = BUTTON_CUTOUT_SIZE + SURFACE * 2;
			outer_height = -BUTTON_Z + BUTTON_CUTOUT_SIZE;
			inner_size = BUTTON_CUTOUT_SIZE + BUTTON_CUTOUT_SIZE_TOLERANCE;
			
			render()
			difference() {
				translate([
					x - outer_width / 2,
					case_inner_depth() - CASE_EXTRA_DEPTH - BUTTON_Y_INSET + SURFACE,
					DISPLAY_Z_PROJECTION - outer_height
				])
				cube([outer_width, BUTTON_Y_INSET - SURFACE, outer_height]);
				
				translate([x - inner_size / 2, case_inner_depth() - CASE_EXTRA_DEPTH - BUTTON_Y_INSET + SURFACE, BUTTON_Z - inner_size / 2])
				cube([inner_size, BUTTON_Y_INSET - SURFACE, inner_size]);
			}	
		}
	}

	render()
	difference() {
		// base
		union() {
			difference() {
				shell(SURFACE);
				shell();
				
				usb_c_hole();
				
				// power button hole
				translate([(case_outer_width() + case_outer_min_x()) / 2, 0, -CASE_HEIGHT / 2])
				rotate([90, 0, 0])
				cylinder(d = POWER_BUTTON_HOLE_DIAMETER, $fn = 36, h = 10);
				
				// don't print a bridge over the USB C hole
				usb_c_bridge();
	
				// cutouts for buttons
				for (button = BUTTONS) {
					if (button[2]) { // visible or not
						x = button[1];
						
						size = BUTTON_CUTOUT_SIZE + BUTTON_CUTOUT_SIZE_TOLERANCE;
						
						translate([x - size / 2, case_inner_depth() - CASE_EXTRA_DEPTH, BUTTON_Z - size / 2])
						cube([size, SURFACE, size]);
					}
				}
			}
			
			// power button standoffs
			for (x = [-POWER_BUTTON_SPACING / 2, POWER_BUTTON_SPACING / 2]) {
				translate([
					(case_outer_width() + case_outer_min_x()) / 2 + x,
					-CASE_EXTRA_DEPTH + POWER_SWITCH_STANDOFF_HEIGHT,
					-CASE_HEIGHT / 2
				])
				rotate([90, 0, 0])
				difference() {
					cylinder(d = 4, h = POWER_SWITCH_STANDOFF_HEIGHT, $fn = 36);
					cylinder(d = 2.45, h = POWER_SWITCH_STANDOFF_HEIGHT, $fn = 36);
				}
			}
			
			union() {
				difference() {
					relative_height = CASE_HEIGHT + USB_C_HOLE_Z + USB_C_HOLE_RADIUS * 2;
					translate([
						case_outer_max_x() - USB_C_EXTRA_DEPTH / 2 - SURFACE / 2,
						case_inner_depth() / 2 + USB_C_HOLE_Y_DELTA,
						-relative_height / 2 + USB_C_HOLE_RADIUS - SURFACE
					])
					cube([USB_C_EXTRA_DEPTH + SURFACE, USB_C_HOLE_WIDTH + USB_C_BRIDGE_EXTRA_WIDTH, relative_height], center = true);
					
					usb_c_hole(1);
					
					// don't print a bridge over the USB C hole
					usb_c_bridge();
				}
			}
		}
			
		light_pipe();
		
		// screen cutout
		translate([
			case_inner_width() / 2 - VIEWABLE_WIDTH / 2 - CASE_EXTRA_WIDTH,
			case_inner_depth() / 2 - VIEWABLE_DEPTH / 2 - CASE_EXTRA_DEPTH,
			DISPLAY_Z_PROJECTION
		])
		hull() {
			cube([VIEWABLE_WIDTH, VIEWABLE_DEPTH, SURFACE]);
			
			translate([-SURFACE, -SURFACE, SURFACE])
			cube([VIEWABLE_WIDTH + SURFACE * 2, VIEWABLE_DEPTH + SURFACE * 2, 0.0001]);
		}
		
		// display standoffs (protrusions into the case)
		for (x = [DISPLAY_STANDOFF_X_INSET, DISPLAY_WIDTH - DISPLAY_STANDOFF_X_INSET]) {
			for (y = [DISPLAY_STANDOFF_Y_INSET, DISPLAY_DEPTH - DISPLAY_STANDOFF_Y_INSET]) {
				translate([x, y, SURFACE - 0.6])
				cylinder(d = 2.4, h = SURFACE - 0.6, $fn = 36);
			}
		}
	}
	
	// display standoffs (just the standoffs)
	for (x = [DISPLAY_STANDOFF_X_INSET, DISPLAY_WIDTH - DISPLAY_STANDOFF_X_INSET]) {
		for (y = [DISPLAY_STANDOFF_Y_INSET, DISPLAY_DEPTH - DISPLAY_STANDOFF_Y_INSET]) {
			translate([x, y, 0])
			render()
			difference() {
				cylinder(d = 5, h = DISPLAY_Z_PROJECTION, $fn = 36);
				cylinder(d = 2.4, h = DISPLAY_Z_PROJECTION, $fn = 36);
			}
		}
	}
	
	// screw standoffs for backplate
	width = SCREW_SHAFT_DIAMETER + 2.5;
	render()
	difference() {
		union() {
			for (x = [SCREW_X_INSET, case_outer_max_x() - SCREW_X_INSET - width / 2]) {
				for (y = [-CASE_EXTRA_DEPTH + SCREW_Y_INSET, case_inner_depth() - CASE_EXTRA_DEPTH - SCREW_Y_INSET]) {
					relative_height = CASE_HEIGHT - SURFACE;
					
					render()
					difference() {
						translate([x, y, -relative_height / 2 + DISPLAY_Z_PROJECTION])
						cube([width, width, relative_height], center = true);
						
						translate([x, y, -relative_height + DISPLAY_Z_PROJECTION])
						cylinder(d = SCREW_SHAFT_DIAMETER, h = relative_height, $fn = 20);
					}
				}
			}
		}
		
		screws();
	}
}

module light_pipe() {
	translate([
		FEATHER_X_OFFSET + FEATHER_WIDTH - 2.5,
		FEATHER_Y_OFFSET + 5.5,
		FEATHER_Z_OFFSET - FEATHER_HEIGHT - FEATHER_PCB_HEIGHT - 2
	])
	rotate([90, 0, 90 - 15])
	cylinder(d = 2, h = 20, $fn = 36);
}

module backplate() {
	render()
	difference() {
		translate([0, 0, -CASE_HEIGHT + DISPLAY_Z_PROJECTION])
		shell(SURFACE, SURFACE, 0);
		
		screws();
		
		// magnet cutouts
		magnets(MAGNET_BUFFER);
	}
	
	// battery standoffs
	translate([
		-CASE_EXTRA_WIDTH,
		0,
		-CASE_HEIGHT + SURFACE + DISPLAY_Z_PROJECTION
	])
	union() {
		for (x = [3, BATTERY_WIDTH - 3]) {
			for (y = [
				case_inner_depth() / 2 - BATTERY_DEPTH / 2 - SURFACE / 2 - 2.5,
				case_inner_depth() / 2 + BATTERY_DEPTH / 2 - SURFACE / 2 + 2.5
			]) {
				translate([x, y, 0])
				render()
				difference() {
					cylinder(d = 4, h = BATTERY_HEIGHT, $fn = 20);
					cylinder(d = 2.5, h = BATTERY_HEIGHT, $fn = 20);
				}
			}
		}
	}
	
	render()
	difference() {	
		usb_c_bridge();
		usb_c_hole();
		light_pipe();
	}
	
	// Feather standoffs
	offsets = [
		[FEATHER_X_OFFSET + 2.55, FEATHER_Y_OFFSET + 1.85, false],
		[FEATHER_X_OFFSET + 48.25, FEATHER_Y_OFFSET + 2.55, false],
		[FEATHER_X_OFFSET + 2.55, FEATHER_Y_OFFSET + 20.95, false],
		[FEATHER_X_OFFSET + 48.25, FEATHER_Y_OFFSET + 20.3, false]
	];
	
	height = -FEATHER_Z_OFFSET - FEATHER_PCB_HEIGHT + 0.9;
	for (offset = offsets) {
		x = offset[0];
		y = offset[1];
		
		translate([x, y, -CASE_HEIGHT + SURFACE + DISPLAY_Z_PROJECTION])
		if (offset[2]) { // true for screw standoff, false for pin
			render()
			difference() {
				cylinder(d = 3.5, h = height, $fn = 20);
				cylinder(d = 2.5, h = height, $fn = 20);
			}
		}
		else {
			union() {
				cylinder(d = 3.5, h = height, $fn = 20);
				cylinder(d = 1.8, h = height + 3, $fn = 20);
			}
		}
	}
}

module screw() {
	cylinder(d = SCREW_SHAFT_DIAMETER, h = SCREW_HEIGHT, $fn = 20);
	cylinder(d1 = SCREW_HEAD_DIAMETER, d2 = SCREW_SHAFT_DIAMETER, h = SCREW_HEAD_HEIGHT, $fn = 20);
}

module screws() {
	width = SCREW_SHAFT_DIAMETER + 2.5;
	for (x = [SCREW_X_INSET, case_outer_max_x() - SCREW_X_INSET - width / 2]) {
		for (y = [-CASE_EXTRA_DEPTH + SCREW_Y_INSET, case_inner_depth() - CASE_EXTRA_DEPTH - SCREW_Y_INSET]) {
			translate([x, y, -CASE_HEIGHT + DISPLAY_Z_PROJECTION])
			screw();
		}
	}
}

module battery() {
	translate([
		BATTERY_WIDTH / 2 - CASE_EXTRA_WIDTH,
		case_inner_depth() / 2 - SURFACE / 2,
		-CASE_HEIGHT + SURFACE + BATTERY_HEIGHT / 2 + DISPLAY_Z_PROJECTION
	])
	cube([BATTERY_WIDTH, BATTERY_DEPTH, BATTERY_HEIGHT], center = true);
}

module battery_strap() {
	render()
	difference() {
		union() {
			hull() {
				translate([
					3 - CASE_EXTRA_WIDTH,
					case_inner_depth() / 2 - BATTERY_DEPTH / 2 - SURFACE / 2 - 2.5,
					-CASE_HEIGHT + SURFACE + DISPLAY_Z_PROJECTION + BATTERY_HEIGHT
				])
				cylinder(d = 4, $fn = 20, h = 1);
				
				translate([
					BATTERY_WIDTH - 3 - CASE_EXTRA_WIDTH,
					case_inner_depth() / 2 + BATTERY_DEPTH / 2 - SURFACE / 2 + 2.5,
					-CASE_HEIGHT + SURFACE + DISPLAY_Z_PROJECTION + BATTERY_HEIGHT
				])
				cylinder(d = 4, $fn = 20, h = 1);
			}
			
			hull() {
				translate([
					BATTERY_WIDTH - 3 - CASE_EXTRA_WIDTH,
					case_inner_depth() / 2 - BATTERY_DEPTH / 2 - SURFACE / 2 - 2.5,
					-CASE_HEIGHT + SURFACE + DISPLAY_Z_PROJECTION + BATTERY_HEIGHT
				])
				cylinder(d = 4, $fn = 20, h = 1);
				
				translate([
					3 - CASE_EXTRA_WIDTH,
					case_inner_depth() / 2 + BATTERY_DEPTH / 2 - SURFACE / 2 + 2.5,
					-CASE_HEIGHT + SURFACE + DISPLAY_Z_PROJECTION + BATTERY_HEIGHT
				])
				cylinder(d = 4, $fn = 20, h = 1);
			}
		}
		
		for (x = [3 - CASE_EXTRA_WIDTH, BATTERY_WIDTH - 3 - CASE_EXTRA_WIDTH]) {
			for (y = [
				case_inner_depth() / 2 - BATTERY_DEPTH / 2 - SURFACE / 2 - 2.5,
				case_inner_depth() / 2 + BATTERY_DEPTH / 2 - SURFACE / 2 + 2.5
			]) {
				translate([x, y, -CASE_HEIGHT + SURFACE + DISPLAY_Z_PROJECTION + BATTERY_HEIGHT])
				cylinder(d = 2.5, $fn = 20, h = 1);
			}
		}
	}
}

module magnet(size_delta = 0) {
	cube([MAGNET_WIDTH + size_delta, MAGNET_DEPTH + size_delta, MAGNET_HEIGHT]);
}

module magnets(size_delta = 0) {
	for (y = [
		MAGNET_Y_INSET - size_delta / 2 - CASE_EXTRA_DEPTH / 2,
		case_inner_depth() - MAGNET_Y_INSET - MAGNET_DEPTH - size_delta / 2 - CASE_EXTRA_DEPTH
	]) {
		translate([MAGNET_X - size_delta / 2, y, -CASE_HEIGHT + SURFACE + DISPLAY_Z_PROJECTION - SURFACE + MAGNET_Z_SPACING])
		magnet(size_delta);
	}
}

module buttons() {
	for (button = BUTTONS) {
		if (button[2]) { // visible or not
			x = button[1];
			
			translate([x, case_inner_depth() - CASE_EXTRA_DEPTH - BUTTON_Y_INSET + SURFACE / 2, BUTTON_Z])
			button();
		}
	}
}

module button() {
	translate([0, SURFACE / 2, 0])
	cube([BUTTON_CUTOUT_SIZE + 1 * 2, SURFACE, BUTTON_CUTOUT_SIZE + 1 * 2], center = true);
	
	translate([0, BUTTON_Y_PROJECTION / 2 + SURFACE, 0])
	cube([BUTTON_CUTOUT_SIZE, BUTTON_Y_PROJECTION, BUTTON_CUTOUT_SIZE], center = true);
}

//color("red") screws();

case();
//buttons();
//backplate();
//battery_strap();

//color("#9999ff") magnets()
//color("#ff9999") battery();
//display();
//color("yellow") feather();