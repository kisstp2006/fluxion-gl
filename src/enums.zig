// SPDX-License-Identifier: CC0-1.0

//! The numbers the commands take, which GL calls enums even though they are
//! one flat numbering shared by every argument of every command.
//!
//! That flatness is worth knowing about: `linear` is a texture filter and
//! `line` is a polygon mode, and nothing but the spelling stops either being
//! passed where the other belongs - the driver answers `invalid_enum` and
//! carries on drawing whatever it drew last. The names are the Khronos ones
//! with `GL_` taken off and lowered.
//!
//! What is here is what the tables in `gl` and `gles` can be passed, a few
//! hundred of the several thousand in the registry. A token that is not here is
//! a number like any other: pass it as a literal.
//!
//! The `_bit` names are ored together into a `Bitfield`; everything else is
//! an `Enum` and stands alone.

const std = @import("std");
const testing = std.testing;

const types = @import("types.zig");

const Bitfield = types.Bitfield;
const Enum = types.Enum;
const Uint = types.Uint;

// -------------------------------------------------------------------------
// Errors, and the values that are their own answer
// -------------------------------------------------------------------------

/// No error since the last time anyone asked. Also "no attachment", "no
/// buffer" and "no texture": zero means nothing, everywhere.
pub const no_error: Enum = 0x0000;
/// Also `GL_NONE`, and the same zero.
pub const none: Enum = 0x0000;

/// A token was not one this command takes.
pub const invalid_enum: Enum = 0x0500;
/// A number was out of range - a negative size, a level past the last one.
pub const invalid_value: Enum = 0x0501;
/// The call was fine and the state was not: no program bound, no context.
pub const invalid_operation: Enum = 0x0502;
/// The framebuffer the command would have drawn to is not complete.
pub const invalid_framebuffer_operation: Enum = 0x0506;
/// The driver could not allocate. Everything after this is undefined.
pub const out_of_memory: Enum = 0x0505;
/// The context was lost - a reset, a suspended device, a driver update - and
/// nothing on it will work again.
pub const context_lost: Enum = 0x0507;

// -------------------------------------------------------------------------
// Strings and integers to ask the context about itself
// -------------------------------------------------------------------------

pub const vendor: Enum = 0x1F00;
pub const renderer: Enum = 0x1F01;
pub const version: Enum = 0x1F02;
/// The flat extension string. Deprecated from OpenGL 3.0 and null in a core
/// profile; see `extensions`.
pub const extensions: Enum = 0x1F03;
pub const shading_language_version: Enum = 0x8B8C;

pub const major_version: Enum = 0x821B;
pub const minor_version: Enum = 0x821C;
/// How many names `getStringi(extensions, i)` will answer for.
pub const num_extensions: Enum = 0x821D;
pub const context_flags: Enum = 0x821E;
pub const context_profile_mask: Enum = 0x9126;

pub const context_core_profile_bit: Bitfield = 0x00000001;
pub const context_compatibility_profile_bit: Bitfield = 0x00000002;
pub const context_flag_forward_compatible_bit: Bitfield = 0x00000001;
pub const context_flag_debug_bit: Bitfield = 0x00000002;
pub const context_flag_robust_access_bit: Bitfield = 0x00000004;

pub const max_texture_size: Enum = 0x0D33;
pub const max_3d_texture_size: Enum = 0x8073;
pub const max_cube_map_texture_size: Enum = 0x851C;
pub const max_array_texture_layers: Enum = 0x88FF;
pub const max_renderbuffer_size: Enum = 0x84E8;
pub const max_texture_image_units: Enum = 0x8872;
pub const max_vertex_texture_image_units: Enum = 0x8B4C;
pub const max_combined_texture_image_units: Enum = 0x8B4D;
pub const max_vertex_attribs: Enum = 0x8869;
pub const max_draw_buffers: Enum = 0x8824;
pub const max_color_attachments: Enum = 0x8CDF;
pub const max_samples: Enum = 0x8D57;
pub const max_elements_indices: Enum = 0x80E9;
pub const max_elements_vertices: Enum = 0x80E8;
pub const max_uniform_block_size: Enum = 0x8A30;
pub const max_vertex_uniform_vectors: Enum = 0x8DFB;
pub const max_varying_vectors: Enum = 0x8DFC;
pub const max_fragment_uniform_vectors: Enum = 0x8DFD;
pub const max_viewport_dims: Enum = 0x0D3A;
pub const uniform_buffer_offset_alignment: Enum = 0x8A34;
pub const implementation_color_read_type: Enum = 0x8B9A;
pub const implementation_color_read_format: Enum = 0x8B9B;
pub const num_program_binary_formats: Enum = 0x87FE;
pub const program_binary_formats: Enum = 0x87FF;
pub const num_shader_binary_formats: Enum = 0x8DF9;
pub const shader_compiler: Enum = 0x8DFA;
pub const subpixel_bits: Enum = 0x0D50;
pub const sample_buffers: Enum = 0x80A8;
pub const samples: Enum = 0x80A9;

// -------------------------------------------------------------------------
// What is bound, and how the pipeline is set
// -------------------------------------------------------------------------

pub const viewport: Enum = 0x0BA2;
pub const scissor_box: Enum = 0x0C10;
pub const depth_range: Enum = 0x0B70;
pub const color_clear_value: Enum = 0x0C22;
pub const depth_clear_value: Enum = 0x0B73;
pub const stencil_clear_value: Enum = 0x0B91;
pub const line_width: Enum = 0x0B21;
pub const cull_face_mode: Enum = 0x0B45;
pub const front_face: Enum = 0x0B46;
pub const depth_func: Enum = 0x0B74;
pub const blend_src_rgb: Enum = 0x80C9;
pub const blend_dst_rgb: Enum = 0x80C8;
pub const blend_src_alpha: Enum = 0x80CB;
pub const blend_dst_alpha: Enum = 0x80CA;
pub const blend_equation_rgb: Enum = 0x8009;
pub const blend_equation_alpha: Enum = 0x883D;
pub const current_program: Enum = 0x8B8D;
pub const array_buffer_binding: Enum = 0x8894;
pub const element_array_buffer_binding: Enum = 0x8895;
pub const uniform_buffer_binding: Enum = 0x8A28;
pub const vertex_array_binding: Enum = 0x85B5;
pub const texture_binding_2d: Enum = 0x8069;
pub const texture_binding_3d: Enum = 0x806A;
pub const texture_binding_cube_map: Enum = 0x8514;
pub const texture_binding_2d_array: Enum = 0x8C1D;
pub const active_texture: Enum = 0x84E0;
pub const sampler_binding: Enum = 0x8919;
pub const framebuffer_binding: Enum = 0x8CA6;
pub const read_framebuffer_binding: Enum = 0x8CAA;
pub const renderbuffer_binding: Enum = 0x8CA7;

// -------------------------------------------------------------------------
// Primitives
// -------------------------------------------------------------------------

pub const points: Enum = 0x0000;
pub const lines: Enum = 0x0001;
pub const line_loop: Enum = 0x0002;
pub const line_strip: Enum = 0x0003;
pub const triangles: Enum = 0x0004;
pub const triangle_strip: Enum = 0x0005;
pub const triangle_fan: Enum = 0x0006;
/// The adjacency modes feed a geometry shader and draw nothing without one.
pub const lines_adjacency: Enum = 0x000A;
pub const line_strip_adjacency: Enum = 0x000B;
pub const triangles_adjacency: Enum = 0x000C;
pub const triangle_strip_adjacency: Enum = 0x000D;
/// For tessellation, where the vertex count per patch is state, not implied.
pub const patches: Enum = 0x000E;

// -------------------------------------------------------------------------
// Buffers: what they are bound as, and what they are for
// -------------------------------------------------------------------------

pub const array_buffer: Enum = 0x8892;
pub const element_array_buffer: Enum = 0x8893;
pub const pixel_pack_buffer: Enum = 0x88EB;
pub const pixel_unpack_buffer: Enum = 0x88EC;
pub const uniform_buffer: Enum = 0x8A11;
pub const copy_read_buffer: Enum = 0x8F36;
pub const copy_write_buffer: Enum = 0x8F37;
pub const transform_feedback_buffer: Enum = 0x8C8E;
pub const texture_buffer: Enum = 0x8C2A;
pub const draw_indirect_buffer: Enum = 0x8F3F;
pub const dispatch_indirect_buffer: Enum = 0x90EE;
pub const shader_storage_buffer: Enum = 0x90D2;
pub const atomic_counter_buffer: Enum = 0x92C0;
pub const query_buffer: Enum = 0x9192;

/// Written once by the application, drawn with a few times.
pub const stream_draw: Enum = 0x88E0;
pub const stream_read: Enum = 0x88E1;
pub const stream_copy: Enum = 0x88E2;
/// Written once, drawn with many times: the mesh that never changes.
pub const static_draw: Enum = 0x88E4;
pub const static_read: Enum = 0x88E5;
pub const static_copy: Enum = 0x88E6;
/// Rewritten and redrawn repeatedly: the vertices of a particle system.
pub const dynamic_draw: Enum = 0x88E8;
pub const dynamic_read: Enum = 0x88E9;
pub const dynamic_copy: Enum = 0x88EA;

pub const buffer_size: Enum = 0x8764;
pub const buffer_usage: Enum = 0x8765;
pub const buffer_mapped: Enum = 0x88BC;

pub const read_only: Enum = 0x88B8;
pub const write_only: Enum = 0x88B9;
pub const read_write: Enum = 0x88BA;

pub const map_read_bit: Bitfield = 0x0001;
pub const map_write_bit: Bitfield = 0x0002;
/// The old contents of the range are not wanted, so the driver need not keep
/// them: the difference between a map that waits for the GPU and one that
/// does not.
pub const map_invalidate_range_bit: Bitfield = 0x0004;
pub const map_invalidate_buffer_bit: Bitfield = 0x0008;
pub const map_flush_explicit_bit: Bitfield = 0x0010;
/// Nothing is synchronised: the application promises the GPU is not reading
/// what it is about to write.
pub const map_unsynchronized_bit: Bitfield = 0x0020;
pub const map_persistent_bit: Bitfield = 0x0040;
pub const map_coherent_bit: Bitfield = 0x0080;
pub const dynamic_storage_bit: Bitfield = 0x0100;
pub const client_storage_bit: Bitfield = 0x0200;

// -------------------------------------------------------------------------
// The types a vertex, a pixel or a uniform is made of
// -------------------------------------------------------------------------

pub const byte: Enum = 0x1400;
pub const unsigned_byte: Enum = 0x1401;
pub const short: Enum = 0x1402;
pub const unsigned_short: Enum = 0x1403;
pub const int: Enum = 0x1404;
pub const unsigned_int: Enum = 0x1405;
pub const float: Enum = 0x1406;
pub const double: Enum = 0x140A;
pub const half_float: Enum = 0x140B;
pub const fixed: Enum = 0x140C;

/// Packed formats: one integer holding several components. The `_rev` is not
/// decoration - it says which end the first component is at.
pub const unsigned_short_5_6_5: Enum = 0x8363;
pub const unsigned_short_4_4_4_4: Enum = 0x8033;
pub const unsigned_short_5_5_5_1: Enum = 0x8034;
pub const unsigned_int_2_10_10_10_rev: Enum = 0x8368;
pub const int_2_10_10_10_rev: Enum = 0x8D9F;
pub const unsigned_int_10f_11f_11f_rev: Enum = 0x8C3B;
pub const unsigned_int_5_9_9_9_rev: Enum = 0x8C3E;
pub const unsigned_int_24_8: Enum = 0x84FA;
pub const float_32_unsigned_int_24_8_rev: Enum = 0x8DAD;

/// The types `getActiveUniform` and `getActiveAttrib` report. `float`, `int`
/// and `unsigned_int` above serve here too - one numbering, one token.
pub const float_vec2: Enum = 0x8B50;
pub const float_vec3: Enum = 0x8B51;
pub const float_vec4: Enum = 0x8B52;
pub const int_vec2: Enum = 0x8B53;
pub const int_vec3: Enum = 0x8B54;
pub const int_vec4: Enum = 0x8B55;
/// `GL_BOOL`, spelled out because `bool` is a Zig type.
pub const boolean: Enum = 0x8B56;
pub const bool_vec2: Enum = 0x8B57;
pub const bool_vec3: Enum = 0x8B58;
pub const bool_vec4: Enum = 0x8B59;
pub const float_mat2: Enum = 0x8B5A;
pub const float_mat3: Enum = 0x8B5B;
pub const float_mat4: Enum = 0x8B5C;
pub const sampler_2d: Enum = 0x8B5E;
pub const sampler_3d: Enum = 0x8B5F;
pub const sampler_cube: Enum = 0x8B60;
pub const sampler_2d_shadow: Enum = 0x8B62;
pub const sampler_2d_array: Enum = 0x8DC1;

// -------------------------------------------------------------------------
// Clearing, and the capabilities that decide what a draw does
// -------------------------------------------------------------------------

pub const depth_buffer_bit: Bitfield = 0x00000100;
pub const stencil_buffer_bit: Bitfield = 0x00000400;
pub const color_buffer_bit: Bitfield = 0x00004000;

pub const blend: Enum = 0x0BE2;
pub const cull_face: Enum = 0x0B44;
pub const depth_test: Enum = 0x0B71;
pub const dither: Enum = 0x0BD0;
pub const polygon_offset_fill: Enum = 0x8037;
pub const sample_alpha_to_coverage: Enum = 0x809E;
pub const sample_coverage: Enum = 0x80A0;
pub const sample_mask: Enum = 0x8E51;
pub const scissor_test: Enum = 0x0C11;
pub const stencil_test: Enum = 0x0B90;
pub const multisample: Enum = 0x809D;
pub const line_smooth: Enum = 0x0B20;
pub const polygon_smooth: Enum = 0x0B41;
pub const depth_clamp: Enum = 0x864F;
pub const primitive_restart: Enum = 0x8F9D;
pub const primitive_restart_fixed_index: Enum = 0x8D69;
pub const rasterizer_discard: Enum = 0x8C89;
pub const framebuffer_srgb: Enum = 0x8DB9;
pub const texture_cube_map_seamless: Enum = 0x884F;
pub const program_point_size: Enum = 0x8642;
pub const debug_output: Enum = 0x92E0;
/// Makes the debug callback run on the thread that made the call, which is
/// what turns a message into a stack trace.
pub const debug_output_synchronous: Enum = 0x8242;

// -------------------------------------------------------------------------
// Blending, depth and stencil
// -------------------------------------------------------------------------

pub const zero: Enum = 0x0000;
pub const one: Enum = 0x0001;
pub const src_color: Enum = 0x0300;
pub const one_minus_src_color: Enum = 0x0301;
pub const src_alpha: Enum = 0x0302;
pub const one_minus_src_alpha: Enum = 0x0303;
pub const dst_alpha: Enum = 0x0304;
pub const one_minus_dst_alpha: Enum = 0x0305;
pub const dst_color: Enum = 0x0306;
pub const one_minus_dst_color: Enum = 0x0307;
pub const src_alpha_saturate: Enum = 0x0308;
pub const constant_color: Enum = 0x8001;
pub const one_minus_constant_color: Enum = 0x8002;
pub const constant_alpha: Enum = 0x8003;
pub const one_minus_constant_alpha: Enum = 0x8004;
pub const src1_color: Enum = 0x88F9;
pub const one_minus_src1_color: Enum = 0x88FA;
pub const src1_alpha: Enum = 0x8589;
pub const one_minus_src1_alpha: Enum = 0x88FB;

pub const func_add: Enum = 0x8006;
pub const min: Enum = 0x8007;
pub const max: Enum = 0x8008;
pub const func_subtract: Enum = 0x800A;
pub const func_reverse_subtract: Enum = 0x800B;

pub const never: Enum = 0x0200;
pub const less: Enum = 0x0201;
pub const equal: Enum = 0x0202;
pub const lequal: Enum = 0x0203;
pub const greater: Enum = 0x0204;
pub const notequal: Enum = 0x0205;
pub const gequal: Enum = 0x0206;
pub const always: Enum = 0x0207;

pub const keep: Enum = 0x1E00;
pub const replace: Enum = 0x1E01;
pub const incr: Enum = 0x1E02;
pub const decr: Enum = 0x1E03;
pub const invert: Enum = 0x150A;
pub const incr_wrap: Enum = 0x8507;
pub const decr_wrap: Enum = 0x8508;

// -------------------------------------------------------------------------
// Faces, winding and polygons
// -------------------------------------------------------------------------

pub const front: Enum = 0x0404;
pub const back: Enum = 0x0405;
pub const front_and_back: Enum = 0x0408;
pub const cw: Enum = 0x0900;
pub const ccw: Enum = 0x0901;
/// Desktop only: ES has no wireframe.
pub const point: Enum = 0x1B00;
pub const line: Enum = 0x1B01;
pub const fill: Enum = 0x1B02;

pub const dont_care: Enum = 0x1100;
pub const fastest: Enum = 0x1101;
pub const nicest: Enum = 0x1102;
pub const generate_mipmap_hint: Enum = 0x8192;

// -------------------------------------------------------------------------
// Textures
// -------------------------------------------------------------------------

pub const texture_1d: Enum = 0x0DE0;
pub const texture_2d: Enum = 0x0DE1;
pub const texture_3d: Enum = 0x806F;
pub const texture_1d_array: Enum = 0x8C18;
pub const texture_2d_array: Enum = 0x8C1A;
pub const texture_rectangle: Enum = 0x84F5;
pub const texture_cube_map: Enum = 0x8513;
pub const texture_cube_map_array: Enum = 0x9009;
pub const texture_2d_multisample: Enum = 0x9100;
pub const texture_2d_multisample_array: Enum = 0x9102;

/// The six faces are consecutive, in this order, which is what makes
/// `cubeFace` a sum rather than a table.
pub const texture_cube_map_positive_x: Enum = 0x8515;
pub const texture_cube_map_negative_x: Enum = 0x8516;
pub const texture_cube_map_positive_y: Enum = 0x8517;
pub const texture_cube_map_negative_y: Enum = 0x8518;
pub const texture_cube_map_positive_z: Enum = 0x8519;
pub const texture_cube_map_negative_z: Enum = 0x851A;

/// Unit zero. The rest are `textureUnit(i)`.
pub const texture0: Enum = 0x84C0;

pub const texture_mag_filter: Enum = 0x2800;
pub const texture_min_filter: Enum = 0x2801;
pub const texture_wrap_s: Enum = 0x2802;
pub const texture_wrap_t: Enum = 0x2803;
pub const texture_wrap_r: Enum = 0x8072;
pub const texture_min_lod: Enum = 0x813A;
pub const texture_max_lod: Enum = 0x813B;
pub const texture_base_level: Enum = 0x813C;
pub const texture_max_level: Enum = 0x813D;
pub const texture_compare_mode: Enum = 0x884C;
pub const texture_compare_func: Enum = 0x884D;
pub const texture_swizzle_r: Enum = 0x8E42;
pub const texture_swizzle_g: Enum = 0x8E43;
pub const texture_swizzle_b: Enum = 0x8E44;
pub const texture_swizzle_a: Enum = 0x8E45;
pub const texture_border_color: Enum = 0x1004;
pub const compare_ref_to_texture: Enum = 0x884E;
/// From an extension so old and so universal that it is in every driver, and
/// still not in core: `GL_EXT_texture_filter_anisotropic`.
pub const texture_max_anisotropy: Enum = 0x84FE;
pub const max_texture_max_anisotropy: Enum = 0x84FF;

pub const nearest: Enum = 0x2600;
pub const linear: Enum = 0x2601;
pub const nearest_mipmap_nearest: Enum = 0x2700;
pub const linear_mipmap_nearest: Enum = 0x2701;
pub const nearest_mipmap_linear: Enum = 0x2702;
pub const linear_mipmap_linear: Enum = 0x2703;

pub const repeat: Enum = 0x2901;
pub const clamp_to_edge: Enum = 0x812F;
pub const clamp_to_border: Enum = 0x812D;
pub const mirrored_repeat: Enum = 0x8370;
pub const mirror_clamp_to_edge: Enum = 0x8743;

// -------------------------------------------------------------------------
// Pixel formats: what is in memory, and what the texture holds
// -------------------------------------------------------------------------

pub const red: Enum = 0x1903;
pub const rg: Enum = 0x8227;
pub const rgb: Enum = 0x1907;
pub const rgba: Enum = 0x1908;
pub const bgr: Enum = 0x80E0;
pub const bgra: Enum = 0x80E1;
pub const alpha: Enum = 0x1906;
pub const luminance: Enum = 0x1909;
pub const luminance_alpha: Enum = 0x190A;
pub const depth_component: Enum = 0x1902;
pub const depth_stencil: Enum = 0x84F9;
pub const stencil_index: Enum = 0x1901;
pub const red_integer: Enum = 0x8D94;
pub const rg_integer: Enum = 0x8228;
pub const rgb_integer: Enum = 0x8D98;
pub const rgba_integer: Enum = 0x8D99;

pub const r8: Enum = 0x8229;
pub const r16: Enum = 0x822A;
pub const rg8: Enum = 0x822B;
pub const rg16: Enum = 0x822C;
pub const r16f: Enum = 0x822D;
pub const r32f: Enum = 0x822E;
pub const rg16f: Enum = 0x822F;
pub const rg32f: Enum = 0x8230;
pub const r8i: Enum = 0x8231;
pub const r8ui: Enum = 0x8232;
pub const r16i: Enum = 0x8233;
pub const r16ui: Enum = 0x8234;
pub const r32i: Enum = 0x8235;
pub const r32ui: Enum = 0x8236;
pub const rg8i: Enum = 0x8237;
pub const rg8ui: Enum = 0x8238;
pub const rg16i: Enum = 0x8239;
pub const rg16ui: Enum = 0x823A;
pub const rg32i: Enum = 0x823B;
pub const rg32ui: Enum = 0x823C;
pub const rgb8: Enum = 0x8051;
pub const rgb565: Enum = 0x8D62;
pub const rgb16f: Enum = 0x881B;
pub const rgb32f: Enum = 0x8815;
pub const rgba4: Enum = 0x8056;
pub const rgb5_a1: Enum = 0x8057;
pub const rgba8: Enum = 0x8058;
pub const rgb10_a2: Enum = 0x8059;
pub const rgb10_a2ui: Enum = 0x906F;
pub const rgba16f: Enum = 0x881A;
pub const rgba32f: Enum = 0x8814;
pub const rgba8i: Enum = 0x8D8E;
pub const rgba8ui: Enum = 0x8D7C;
pub const rgba16i: Enum = 0x8D88;
pub const rgba16ui: Enum = 0x8D76;
pub const rgba32i: Enum = 0x8D82;
pub const rgba32ui: Enum = 0x8D70;
pub const r11f_g11f_b10f: Enum = 0x8C3A;
pub const rgb9_e5: Enum = 0x8C3D;
/// The sRGB formats are the whole of colour correctness in OpenGL: sampling
/// one converts to linear, and `framebuffer_srgb` converts back on the way
/// out. An 8-bit texture that is not one of these and is treated as linear is
/// the usual reason a picture looks washed out.
pub const srgb: Enum = 0x8C40;
pub const srgb8: Enum = 0x8C41;
pub const srgb_alpha: Enum = 0x8C42;
pub const srgb8_alpha8: Enum = 0x8C43;

pub const depth_component16: Enum = 0x81A5;
pub const depth_component24: Enum = 0x81A6;
pub const depth_component32f: Enum = 0x8CAC;
pub const depth24_stencil8: Enum = 0x88F0;
pub const depth32f_stencil8: Enum = 0x8CAD;
pub const stencil_index8: Enum = 0x8D48;

pub const unpack_alignment: Enum = 0x0CF5;
pub const unpack_row_length: Enum = 0x0CF2;
pub const unpack_skip_rows: Enum = 0x0CF3;
pub const unpack_skip_pixels: Enum = 0x0CF4;
pub const pack_alignment: Enum = 0x0D05;
pub const pack_row_length: Enum = 0x0D02;
pub const pack_skip_rows: Enum = 0x0D03;
pub const pack_skip_pixels: Enum = 0x0D04;

// -------------------------------------------------------------------------
// Shaders and programs
// -------------------------------------------------------------------------

pub const fragment_shader: Enum = 0x8B30;
pub const vertex_shader: Enum = 0x8B31;
pub const geometry_shader: Enum = 0x8DD9;
pub const tess_control_shader: Enum = 0x8E88;
pub const tess_evaluation_shader: Enum = 0x8E87;
pub const compute_shader: Enum = 0x91B9;

pub const shader_type: Enum = 0x8B4F;
pub const delete_status: Enum = 0x8B80;
/// Ask for this after every `compileShader`, always. A shader that failed to
/// compile is not an error the driver raises; it is a program that draws
/// nothing.
pub const compile_status: Enum = 0x8B81;
pub const link_status: Enum = 0x8B82;
pub const validate_status: Enum = 0x8B83;
pub const info_log_length: Enum = 0x8B84;
pub const shader_source_length: Enum = 0x8B88;
pub const attached_shaders: Enum = 0x8B85;
pub const active_uniforms: Enum = 0x8B86;
pub const active_uniform_max_length: Enum = 0x8B87;
pub const active_attributes: Enum = 0x8B89;
pub const active_attribute_max_length: Enum = 0x8B8A;
pub const program_binary_length: Enum = 0x8741;
pub const low_float: Enum = 0x8DF0;
pub const medium_float: Enum = 0x8DF1;
pub const high_float: Enum = 0x8DF2;
pub const low_int: Enum = 0x8DF3;
pub const medium_int: Enum = 0x8DF4;
pub const high_int: Enum = 0x8DF5;

pub const vertex_attrib_array_enabled: Enum = 0x8622;
pub const vertex_attrib_array_size: Enum = 0x8623;
pub const vertex_attrib_array_stride: Enum = 0x8624;
pub const vertex_attrib_array_type: Enum = 0x8625;
pub const vertex_attrib_array_normalized: Enum = 0x886A;
pub const vertex_attrib_array_buffer_binding: Enum = 0x889F;
pub const vertex_attrib_array_divisor: Enum = 0x88FE;

pub const interleaved_attribs: Enum = 0x8C8C;
pub const separate_attribs: Enum = 0x8C8D;

// -------------------------------------------------------------------------
// Framebuffers and renderbuffers
// -------------------------------------------------------------------------

pub const framebuffer: Enum = 0x8D40;
pub const read_framebuffer: Enum = 0x8CA8;
pub const draw_framebuffer: Enum = 0x8CA9;
pub const renderbuffer: Enum = 0x8D41;

/// Attachment zero. The rest are `colorAttachment(i)`.
pub const color_attachment0: Enum = 0x8CE0;
pub const depth_attachment: Enum = 0x8D00;
pub const stencil_attachment: Enum = 0x8D20;
pub const depth_stencil_attachment: Enum = 0x821A;

pub const framebuffer_complete: Enum = 0x8CD5;
pub const framebuffer_undefined: Enum = 0x8219;
pub const framebuffer_incomplete_attachment: Enum = 0x8CD6;
pub const framebuffer_incomplete_missing_attachment: Enum = 0x8CD7;
pub const framebuffer_incomplete_draw_buffer: Enum = 0x8CDB;
pub const framebuffer_incomplete_read_buffer: Enum = 0x8CDC;
pub const framebuffer_unsupported: Enum = 0x8CDD;
pub const framebuffer_incomplete_multisample: Enum = 0x8D56;

pub const renderbuffer_width: Enum = 0x8D42;
pub const renderbuffer_height: Enum = 0x8D43;
pub const renderbuffer_internal_format: Enum = 0x8D44;
pub const renderbuffer_samples: Enum = 0x8CAB;

/// Draw buffer zero. The rest are consecutive.
pub const draw_buffer0: Enum = 0x8825;
pub const color: Enum = 0x1800;
pub const depth: Enum = 0x1801;
pub const stencil: Enum = 0x1802;

// -------------------------------------------------------------------------
// Queries, sync and timers
// -------------------------------------------------------------------------

pub const samples_passed: Enum = 0x8914;
pub const any_samples_passed: Enum = 0x8C2F;
pub const any_samples_passed_conservative: Enum = 0x8D6A;
pub const primitives_generated: Enum = 0x8C87;
pub const transform_feedback_primitives_written: Enum = 0x8C88;
pub const time_elapsed: Enum = 0x88BF;
pub const timestamp: Enum = 0x8E28;
pub const query_result: Enum = 0x8866;
/// Ask this first: reading `query_result` before the answer is ready stalls
/// until it is, which is the thing a query was meant to avoid.
pub const query_result_available: Enum = 0x8867;

pub const sync_gpu_commands_complete: Enum = 0x9117;
pub const sync_flush_commands_bit: Bitfield = 0x00000001;
pub const already_signaled: Enum = 0x911A;
pub const timeout_expired: Enum = 0x911B;
pub const condition_satisfied: Enum = 0x911C;
pub const wait_failed: Enum = 0x911D;
/// The timeout that means "as long as it takes", for `waitSync`.
pub const timeout_ignored: u64 = 0xFFFFFFFFFFFFFFFF;

// -------------------------------------------------------------------------
// Debug output
// -------------------------------------------------------------------------

pub const debug_source_api: Enum = 0x8246;
pub const debug_source_window_system: Enum = 0x8247;
pub const debug_source_shader_compiler: Enum = 0x8248;
pub const debug_source_third_party: Enum = 0x8249;
pub const debug_source_application: Enum = 0x824A;
pub const debug_source_other: Enum = 0x824B;

pub const debug_type_error: Enum = 0x824C;
pub const debug_type_deprecated_behavior: Enum = 0x824D;
pub const debug_type_undefined_behavior: Enum = 0x824E;
pub const debug_type_portability: Enum = 0x824F;
pub const debug_type_performance: Enum = 0x8250;
pub const debug_type_other: Enum = 0x8251;
pub const debug_type_marker: Enum = 0x8268;
pub const debug_type_push_group: Enum = 0x8269;
pub const debug_type_pop_group: Enum = 0x826A;

pub const debug_severity_high: Enum = 0x9146;
pub const debug_severity_medium: Enum = 0x9147;
pub const debug_severity_low: Enum = 0x9148;
/// Everything the driver thinks you might like to know, which on some drivers
/// is every buffer allocation. Filter it off in a release build.
pub const debug_severity_notification: Enum = 0x826B;

pub const max_debug_message_length: Enum = 0x9143;
pub const max_debug_logged_messages: Enum = 0x9144;
pub const debug_logged_messages: Enum = 0x9145;

/// What kind of object `objectLabel` is naming. Khronos calls these `GL_BUFFER`
/// and `GL_TEXTURE`; they carry `_object` here because a flat namespace that
/// already has a `texture_2d` and a `buffer_size` has no room for a token
/// called `buffer`. `framebuffer` and `renderbuffer` are the same tokens as
/// the bind targets, and are declared above.
pub const buffer_object: Enum = 0x82E0;
pub const shader_object: Enum = 0x82E1;
pub const program_object: Enum = 0x82E2;
pub const query_object: Enum = 0x82E3;
pub const program_pipeline_object: Enum = 0x82E4;
pub const sampler_object: Enum = 0x82E6;
pub const texture_object: Enum = 0x1702;
pub const vertex_array_object: Enum = 0x8074;

// -------------------------------------------------------------------------
// Compute and memory barriers
// -------------------------------------------------------------------------

pub const max_compute_work_group_count: Enum = 0x91BE;
pub const max_compute_work_group_size: Enum = 0x91BF;
pub const max_compute_work_group_invocations: Enum = 0x90EB;

pub const vertex_attrib_array_barrier_bit: Bitfield = 0x00000001;
pub const element_array_barrier_bit: Bitfield = 0x00000002;
pub const uniform_barrier_bit: Bitfield = 0x00000004;
pub const texture_fetch_barrier_bit: Bitfield = 0x00000008;
pub const shader_image_access_barrier_bit: Bitfield = 0x00000020;
pub const command_barrier_bit: Bitfield = 0x00000040;
pub const pixel_buffer_barrier_bit: Bitfield = 0x00000080;
pub const texture_update_barrier_bit: Bitfield = 0x00000100;
pub const buffer_update_barrier_bit: Bitfield = 0x00000200;
pub const framebuffer_barrier_bit: Bitfield = 0x00000400;
pub const transform_feedback_barrier_bit: Bitfield = 0x00000800;
pub const atomic_counter_barrier_bit: Bitfield = 0x00001000;
pub const shader_storage_barrier_bit: Bitfield = 0x00002000;
pub const all_barrier_bits: Bitfield = 0xFFFFFFFF;

// -------------------------------------------------------------------------
// The tokens that are defined as a sum
// -------------------------------------------------------------------------

/// `GL_TEXTURE0 + index`, which is how the specification defines every unit
/// after the first. There is no table of them, and a driver with 192 units
/// would need a long one.
pub fn textureUnit(index: Uint) Enum {
    return texture0 + index;
}

/// `GL_COLOR_ATTACHMENT0 + index`.
pub fn colorAttachment(index: Uint) Enum {
    return color_attachment0 + index;
}

/// `GL_DRAW_BUFFER0 + index`.
pub fn drawBufferSlot(index: Uint) Enum {
    return draw_buffer0 + index;
}

/// `GL_TEXTURE_CUBE_MAP_POSITIVE_X + face`, for a face in 0..6: +X, -X, +Y,
/// -Y, +Z, -Z, in that order.
pub fn cubeFace(face: Uint) Enum {
    return texture_cube_map_positive_x + face;
}

// -------------------------------------------------------------------------
// Tests
// -------------------------------------------------------------------------

test "the sums are the tokens they should be" {
    try testing.expectEqual(texture0, textureUnit(0));
    try testing.expectEqual(0x84C1, textureUnit(1));
    try testing.expectEqual(0x84DF, textureUnit(31));

    try testing.expectEqual(color_attachment0, colorAttachment(0));
    try testing.expectEqual(0x8CE7, colorAttachment(7));
    try testing.expectEqual(draw_buffer0, drawBufferSlot(0));

    try testing.expectEqual(texture_cube_map_positive_x, cubeFace(0));
    try testing.expectEqual(texture_cube_map_negative_x, cubeFace(1));
    try testing.expectEqual(texture_cube_map_negative_z, cubeFace(5));
}

test "the values that everything else is checked against" {
    // If any of these have drifted, the file was edited by hand and wrongly:
    // they are the ones a person would notice, and they anchor the rest.
    try testing.expectEqual(0x1406, float);
    try testing.expectEqual(0x1401, unsigned_byte);
    try testing.expectEqual(0x0004, triangles);
    try testing.expectEqual(0x8892, array_buffer);
    try testing.expectEqual(0x8893, element_array_buffer);
    try testing.expectEqual(0x8B31, vertex_shader);
    try testing.expectEqual(0x8B30, fragment_shader);
    try testing.expectEqual(0x0DE1, texture_2d);
    try testing.expectEqual(0x8D40, framebuffer);
    try testing.expectEqual(0x8CD5, framebuffer_complete);
    try testing.expectEqual(0x1F02, version);
}

test "the bits are bits" {
    // Nothing that goes into the same mask may overlap.
    try testing.expectEqual(0, color_buffer_bit & depth_buffer_bit);
    try testing.expectEqual(0, color_buffer_bit & stencil_buffer_bit);
    try testing.expectEqual(0, depth_buffer_bit & stencil_buffer_bit);
    try testing.expectEqual(0x4500, color_buffer_bit | depth_buffer_bit | stencil_buffer_bit);

    try testing.expectEqual(0, map_read_bit & map_write_bit);
    try testing.expectEqual(0, map_invalidate_range_bit & map_invalidate_buffer_bit);

    // And the mask that means everything covers each of them.
    inline for (.{
        vertex_attrib_array_barrier_bit,
        uniform_barrier_bit,
        shader_storage_barrier_bit,
        framebuffer_barrier_bit,
    }) |bit| {
        try testing.expectEqual(bit, all_barrier_bits & bit);
    }
}

test "no two names in one group share a value" {
    // A copied line with an unchanged value is the mistake this file invites,
    // and it is silent: the driver takes the number, not the name.
    const filters = [_]Enum{
        nearest,
        linear,
        nearest_mipmap_nearest,
        linear_mipmap_nearest,
        nearest_mipmap_linear,
        linear_mipmap_linear,
    };
    for (filters, 0..) |a, i| {
        for (filters[i + 1 ..]) |b| try testing.expect(a != b);
    }

    const formats = [_]Enum{ r8, rg8, rgb8, rgba8, srgb8, srgb8_alpha8, rgba16f, rgba32f, rgb10_a2, depth24_stencil8 };
    for (formats, 0..) |a, i| {
        for (formats[i + 1 ..]) |b| try testing.expect(a != b);
    }

    const primitives = [_]Enum{ points, lines, line_loop, line_strip, triangles, triangle_strip, triangle_fan };
    for (primitives, 0..) |a, i| {
        for (primitives[i + 1 ..]) |b| try testing.expect(a != b);
    }

    // The `objectLabel` identifiers, which include two tokens that are spelled
    // as bind targets everywhere else.
    const labels = [_]Enum{
        buffer_object,
        shader_object,
        program_object,
        query_object,
        program_pipeline_object,
        sampler_object,
        texture_object,
        vertex_array_object,
        framebuffer,
        renderbuffer,
    };
    for (labels, 0..) |a, i| {
        for (labels[i + 1 ..]) |b| try testing.expect(a != b);
    }
}
