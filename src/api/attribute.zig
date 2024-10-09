pub const Attribute = union(enum) {
    standard: Standard,
    dynamic: Dynamic,

    pub fn listFromStruct(attributes: anytype) [@typeInfo(@TypeOf(attributes)).Struct.fields.len]Attribute {
        const struct_info = @typeInfo(@TypeOf(attributes)).Struct;
        const num_attributes = struct_info.fields.len;

        var attrs: [num_attributes]Attribute = undefined;
        inline for (attrs[0..], struct_info.fields) |*attribute, field| {
            if (@hasField(Standard, field.name)) {
                attribute.* = .{ .standard = @unionInit(Standard, field.name, @field(attributes, field.name)) };
            } else {
                attribute.* = .{ .dynamic = .{
                    .key = field.name,
                    .value = Attribute.Value.fromType(field.type, @field(attributes, field.name)),
                } };
            }
        }

        return attrs;
    }

    pub fn listFromSourceLocation(src: std.builtin.SourceLocation) [4]Attribute {
        return [4]Attribute{
            .{ .standard = .{ .@"code.filepath" = src.file } },
            .{ .standard = .{ .@"code.function" = src.fn_name } },
            .{ .standard = .{ .@"code.lineno" = src.line } },
            .{ .standard = .{ .@"code.column" = src.column } },
        };
    }
};

pub const Type = enum {
    // ------ primitive types ------

    string,
    boolean,
    double,
    integer,

    // --- primitive array types ---

    string_array,
    boolean_array,
    double_array,
    integer_array,
};

/// This type makes no claims about data ownership. See attribute.Set for a type that owns its data.
pub const Dynamic = union(enum) {
    key: []const u8,
    value: Value,

    pub const Value = union(Type) {
        // ------ primitive types ------

        string: []const u8,
        boolean: bool,
        double: f64,
        integer: i64,

        // --- primitive array types ---

        string_array: []const []const u8,
        boolean_array: []const bool,
        double_array: []const f64,
        integer_array: []const i64,

        pub fn fromType(T: type, val: T) @This() {
            switch (T) {
                []const u8 => return .{ .string = val },
                bool => return .{ .boolean = val },
                f16, f32, f64, comptime_float => return .{ .double = val },
                i32, i64, comptime_int => return .{ .integer = val },

                []const []const u8 => return .{ .string_array = val },
                []const bool => return .{ .boolean_array = val },
                []const f64 => return .{ .double_array = val },
                []const i64, []const comptime_int => return .{ .integer_array = val },
                else => switch (@typeInfo(T)) {
                    // enums are string encoded
                    .Enum => return .{ .string = @tagName(val) },

                    else => @compileError("unsupported type" ++ @typeName(T)),
                },
            }
        }

        pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            switch (value) {
                .string => |s| try writer.print("{}", .{std.zig.fmtEscapes(s)}),
                .boolean => |b| try writer.print("{}", .{b}),
                .double => |d| try writer.print("{e}", .{d}),
                .integer => |i| try writer.print("{}", .{i}),

                .string_array => |array| {
                    try writer.writeAll("{");
                    for (array) |string| {
                        try writer.print(" \"{}\"", .{std.zig.fmtEscapes(string)});
                    }
                    try writer.writeAll(" }");
                },
                .boolean_array => |array| {
                    try writer.writeAll("{");
                    for (array) |boolean| {
                        try writer.print(" {}", .{boolean});
                    }
                    try writer.writeAll(" }");
                },
                .double_array => |array| {
                    try writer.writeAll("{");
                    for (array) |double| {
                        try writer.print(" {e}", .{double});
                    }
                    try writer.writeAll(" }");
                },
                .integer_array => |array| {
                    try writer.writeAll("{");
                    for (array) |integer| {
                        try writer.print(" {d}", .{integer});
                    }
                    try writer.writeAll(" }");
                },
            }
        }

        pub fn jsonStringify(this: @This(), jw: anytype) !void {
            try jw.beginObject();
            switch (this) {
                .string => |s| {
                    try jw.objectField("stringValue");
                    try jw.write(s);
                },
                .boolean => |b| {
                    try jw.objectField("boolValue");
                    try jw.write(b);
                },
                .double => |d| {
                    try jw.objectField("doubleValue");
                    try jw.write(d);
                },
                .integer => |i| {
                    try jw.objectField("intValue");
                    try jw.write(i);
                },
                .string_array => |array| {
                    try jw.objectField("arrayValue");
                    try jw.beginObject();
                    try jw.objectField("values");
                    try jw.beginArray();
                    for (array) |string| {
                        try jw.write(Value{ .string = string });
                    }
                    try jw.endArray();
                    try jw.endObject();
                },
                .boolean_array => |array| {
                    try jw.objectField("arrayValue");
                    try jw.beginObject();
                    try jw.objectField("values");
                    try jw.beginArray();
                    for (array) |boolean| {
                        try jw.write(Value{ .boolean = boolean });
                    }
                    try jw.endArray();
                    try jw.endObject();
                },
                .double_array => |array| {
                    try jw.objectField("arrayValue");
                    try jw.beginObject();
                    try jw.objectField("values");
                    try jw.beginArray();
                    for (array) |double| {
                        try jw.write(Value{ .double = double });
                    }
                    try jw.endArray();
                    try jw.endObject();
                },
                .integer_array => |array| {
                    try jw.objectField("arrayValue");
                    try jw.beginObject();
                    try jw.objectField("values");
                    try jw.beginArray();
                    for (array) |integer| {
                        try jw.write(Value{ .integer = integer });
                    }
                    try jw.endArray();
                    try jw.endObject();
                },
            }
            try jw.endObject();
        }
    };

    pub fn format(attr: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}={}", .{ attr.key, attr.value });
    }
};

/// Standard Attribute names.
///
/// Is a 31-bit integer for `Attribute.Set`. This allows using one bit of a 32-bit integer to both
/// reference standard attribute names and index into a string table for custom attribute names.
pub const Standard = union(enum(u31)) {
    pub const Name = std.meta.Tag(Standard);

    // --- service group (stable) ---
    @"service.name": []const u8,
    @"service.version": []const u8,

    // --- telemetry group (stable) ---

    @"telemetry.sdk.language": []const u8,
    @"telemetry.sdk.name": []const u8,
    @"telemetry.sdk.version": []const u8,

    // --- server group (stable) ---
    @"server.address": []const u8,
    @"server.port": i64,

    // --- client group (stable) ---

    @"client.address": []const u8,
    @"client.port": i64,

    // --- network group (stable) ---

    @"network.local.address": []const u8,
    @"network.local.port": i64,
    @"network.peer.address": []const u8,
    @"network.peer.port": i64,
    @"network.protocol.name": []const u8,
    @"network.protocol.version": []const u8,
    /// Should be serialized as a string.
    @"network.transport": enum {
        pipe,
        tcp,
        udp,
        unix,
    },
    @"network.type": enum {
        ipv4,
        ipv6,
    },

    // ---- code group (experimental) ----

    /// (experimental) The source code file name that identifies the code unit as
    /// uniquely as possible (preferably an absolute file path).
    @"code.filepath": []const u8,
    /// (experimental)
    @"code.function": []const u8,
    /// (experimental) The line number in code.filepath best representing the operation.
    /// It SHOULD point within the code unit named in code.function.
    @"code.lineno": i64,
    /// (experimental) The column number in code.filepath best representing the
    /// operation. It SHOULD point within the code unit named in code.function.
    @"code.column": i64,
    /// (experimental)
    @"code.namespace": []const u8,
    /// (experimental)
    @"code.stacktrace": []const u8,

    // ------ error group ------

    @"error.type": []const u8,

    // ------ exception group ------

    /// The exception message.
    @"exception.message": []const u8,
    /// The exceptions type. We use the error for this in Zig.
    @"exception.type": []const u8,
    @"exception.escaped": bool,
    /// SHOULD be set to true if the exception event is recorded at a point where it is
    /// known that the exception is escaping the scope of the span.
    ///
    /// An exception is considered to have escaped (or left) the scope of a span, if that
    /// span is ended while the exception is still logically “in flight”. This may be
    /// actually “in flight” in some languages (e.g. if the exception is passed to a
    /// Context manager’s __exit__ method in Python) but will usually be caught at the
    /// point of recording the exception in most languages.
    @"exception.stacktrace": []const u8,

    // ------ http group ------

    /// Should be serialized as a string. "_OTHER" is used for unknown http methods.
    @"http.request.method": std.http.Method,
    @"http.request.method_original": []const u8,
    /// [HTTP response status code](https://datatracker.ietf.org/doc/html/rfc7231#section-6)
    @"http.request.status_code": i64,
    @"http.request.resend_count": i64,

    // ------ url group ------

    @"url.full": []const u8,
    @"url.scheme": []const u8,
    @"url.path": []const u8,
    @"url.query": []const u8,
    @"url.fragment": []const u8,

    // ------ user_agent group ------

    @"user_agent.original": []const u8,

    pub fn asDynamicValue(this: @This()) Dynamic.Value {
        switch (this) {
            inline else => |val| return Dynamic.Value.fromType(@TypeOf(val), val),
        }
    }
};

/// A self contained set of attributes.
///
/// Converts standard attribute strings into an enum type with statically allocated strings.
///
/// Owns all the runtime memory it references. Must be passed the same allocator it was initialized with.
pub const Set = struct {
    kv: std.ArrayHashMapUnmanaged(Key, Set.Value, StringTableContext, false) = .{},
    string_table: std.ArrayListUnmanaged(u8) = .{},
    value_table: std.ArrayListUnmanaged(u8) = .{},
    dropped_attribute_count: u32 = 0,

    pub fn ensureTotalCapacity(this: *@This(), allocator: std.mem.Allocator, max_attributes: usize, max_string_bytes: usize, max_value_bytes: usize) !void {
        try this.kv.ensureTotalCapacityContext(allocator, max_attributes, StringTableContext{ .string_table = this.string_table.items });
        try this.string_table.ensureTotalCapacity(allocator, max_string_bytes);
        try this.value_table.ensureTotalCapacity(allocator, max_value_bytes);
    }

    pub fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
        this.kv.deinit(allocator);
        this.string_table.deinit(allocator);
        this.value_table.deinit(allocator);
    }

    pub fn clone(this: @This(), allocator: std.mem.Allocator) !@This() {
        var kv_clone = try this.kv.cloneContext(allocator, .{ .string_table = this.string_table.items });
        errdefer kv_clone.deinit(allocator);

        var string_table_clone = try this.string_table.clone(allocator);
        errdefer string_table_clone.deinit(allocator);

        var value_table_clone = try this.value_table.clone(allocator);
        errdefer value_table_clone.deinit(allocator);

        return .{
            .kv = kv_clone,
            .string_table = string_table_clone,
            .value_table = value_table_clone,
        };
    }

    pub fn put(this: *@This(), attribute: Attribute) void {
        if (this.kv.count() + 1 > this.kv.capacity()) {
            this.dropped_attribute_count += 1;
            return;
        }

        const dynamic_value = switch (attribute) {
            .standard => |standard| standard.asDynamicValue(),
            .dynamic => |dynamic| dynamic.value,
        };

        // write the value into the value table, but leave them in the unused capacity slice until
        // we verify that we can fit the new key
        const value_start_index = this.value_table.items.len;
        const unused_value_bytes = this.value_table.unusedCapacitySlice();
        var value_end_index: usize = 0;
        const value: Set.Value = switch (dynamic_value) {
            .string => |s| blk: {
                if (s.len > unused_value_bytes.len) {
                    this.dropped_attribute_count += 1;
                    return;
                }
                @memcpy(unused_value_bytes[0..s.len], s);
                value_end_index += s.len;
                break :blk .{ .string = .{ .idx = @intCast(value_start_index), .len = @intCast(s.len) } };
            },
            .boolean => |b| .{ .boolean = b },
            .double => |d| .{ .double = d },
            .integer => |i| .{ .integer = i },

            .string_array => |array| blk: {
                for (array, 0..) |string, i| {
                    if (value_end_index + string.len + 1 > unused_value_bytes.len) {
                        this.dropped_attribute_count += 1;
                        return;
                    }
                    if (i > 0) {
                        unused_value_bytes[value_end_index] = 0;
                        value_end_index += 1;
                    }
                    @memcpy(unused_value_bytes[value_end_index..][0..string.len], string);
                    value_end_index += string.len;
                }
                break :blk .{ .string_array = .{ .idx = @intCast(value_start_index), .len = @intCast(value_end_index - value_start_index) } };
            },
            .boolean_array => |src_array| blk: {
                if (src_array.len > unused_value_bytes.len) {
                    this.dropped_attribute_count += 1;
                    return;
                }
                const dst_array = unused_value_bytes[value_end_index..][0..src_array.len];
                for (dst_array, src_array) |*dst, src| {
                    dst.* = @intFromBool(src);
                }

                value_end_index += src_array.len;

                break :blk .{ .boolean_array = .{ .idx = @intCast(value_start_index), .len = @intCast(src_array.len) } };
            },
            .double_array => |array| blk: {
                const aligned_start = std.mem.alignForward(usize, value_start_index, 8);
                if (aligned_start + array.len * @sizeOf(f64) > unused_value_bytes.len) {
                    this.dropped_attribute_count += 1;
                    return;
                }

                value_end_index = aligned_start;
                const table_bytes = unused_value_bytes[aligned_start..];
                const dst_array = @as([*]f64, @ptrCast(@alignCast(table_bytes.ptr)))[0..array.len];
                @memcpy(dst_array, array);
                value_end_index += array.len * @sizeOf(f64);

                break :blk .{ .double_array = .{ .idx = @intCast(aligned_start), .len = @intCast(value_end_index - aligned_start) } };
            },
            .integer_array => |array| blk: {
                const aligned_start = std.mem.alignForward(usize, value_start_index, 8);
                if (aligned_start + array.len * @sizeOf(i64) > unused_value_bytes.len) {
                    this.dropped_attribute_count += 1;
                    return;
                }

                value_end_index = aligned_start;
                const table_bytes = unused_value_bytes[aligned_start..];
                const dst_array = @as([*]i64, @ptrCast(@alignCast(table_bytes.ptr)))[0..array.len];
                @memcpy(dst_array, array);
                value_end_index += array.len * @sizeOf(f64);

                break :blk .{ .integer_array = .{ .idx = @intCast(aligned_start), .len = @intCast(value_end_index - aligned_start) } };
            },
        };

        const unused_string_bytes = this.string_table.unusedCapacitySlice();
        var string_end_index: usize = 0;
        const key = write_key_string: {
            switch (attribute) {
                .standard => |standard| {
                    break :write_key_string Key{ .type = .standard, .data = .{ .standard = standard } };
                },
                .dynamic => |dynamic| {
                    if (dynamic.key.len == 0) return;
                    if (std.meta.stringToEnum(Standard.Name, dynamic.key)) |standard_key| {
                        break :write_key_string Key{ .type = .standard, .data = .{ .standard = standard_key } };
                    }
                    if (dynamic.key.len + 1 > unused_string_bytes.len) {
                        this.dropped_attribute_count += 1;
                        return;
                    }
                    @memcpy(unused_value_bytes[0..dynamic.key.len], dynamic.key);
                    unused_value_bytes[dynamic.key.len] = 0;
                    string_end_index += dynamic.key.len + 1;

                    break :write_key_string Key{ .type = .custom, .data = .{ .custom = @enumFromInt(this.string_table.items.len) } };
                },
            }
        };

        // finalize writes
        this.string_table.items.len += string_end_index;
        this.value_table.items.len += value_end_index;
        this.kv.putAssumeCapacityContext(key, value, .{ .string_table = this.string_table.items });
    }

    /// Asserts that all attribute keys are larger than 0.
    pub fn fromList(allocator: std.mem.Allocator, list: []const Attribute) !Set {
        var set: Set = .{};
        errdefer set.deinit(allocator);
        for (list) |attr| {
            const context = StringTableContext{ .string_table = set.string_table.items };
            const gop = if (attr == .standard)
                try set.kv.getOrPutContext(allocator, .{ .type = .standard, .data = .{ .standard = attr.standard } }, context)
            else get_dynamic: {
                std.debug.assert(attr.dynamic.key.len > 0);
                const adapter = StringTableAdapter{ .string_table = set.string_table.items };
                const gop = try set.kv.getOrPutContextAdapted(allocator, attr.dynamic.key, adapter, context);
                if (!gop.found_existing) {
                    if (std.meta.stringToEnum(Standard.Name, attr.dynamic.key)) |standard_key| {
                        gop.key_ptr.* = .{ .type = .standard, .data = .{ .standard = standard_key } };
                    } else {
                        try set.string_table.ensureUnusedCapacity(allocator, attr.dynamic.key.len + 1);
                        const index = set.string_table.items.len;
                        set.string_table.appendSliceAssumeCapacity(attr.dynamic.key);
                        set.string_table.appendAssumeCapacity(0);
                        gop.key_ptr.* = .{ .type = .custom, .data = .{ .custom = @enumFromInt(index) } };
                    }
                }
                break :get_dynamic gop;
            };

            const dynamic_value = switch (attr) {
                .standard => |standard| standard.asDynamicValue(),
                .dynamic => |dynamic| dynamic.value,
            };

            switch (dynamic_value) {
                .string => |s| {
                    const start_index: u32 = @intCast(set.value_table.items.len);
                    try set.value_table.appendSlice(allocator, s);
                    gop.value_ptr.* = .{ .string = .{ .idx = start_index, .len = @intCast(s.len) } };
                },
                .boolean => |b| gop.value_ptr.* = .{ .boolean = b },
                .double => |d| gop.value_ptr.* = .{ .double = d },
                .integer => |i| gop.value_ptr.* = .{ .integer = i },

                .string_array => |array| {
                    const start_index: u32 = @intCast(set.value_table.items.len);
                    for (array, 0..) |string, i| {
                        if (i > 0) try set.value_table.append(allocator, 0);
                        try set.value_table.appendSlice(allocator, string);
                    }
                    const len: u32 = @intCast(set.value_table.items.len - start_index);
                    gop.value_ptr.* = .{ .string_array = .{ .idx = start_index, .len = len } };
                },
                .boolean_array => |src_array| {
                    const start_index: u32 = @intCast(set.value_table.items.len);
                    const dst_array = try set.value_table.addManyAsSlice(allocator, src_array.len);
                    for (dst_array, src_array) |*dst, src| {
                        dst.* = @intFromBool(src);
                    }
                    gop.value_ptr.* = .{ .boolean_array = .{ .idx = start_index, .len = @intCast(src_array.len) } };
                },
                .double_array => |array| {
                    try set.value_table.resize(allocator, std.mem.alignForward(usize, set.value_table.items.len, 8));

                    const start_index: u32 = @intCast(set.value_table.items.len);
                    const table_bytes = try set.value_table.addManyAsSlice(allocator, array.len * 8);
                    const dst_array = @as([*]f64, @ptrCast(@alignCast(table_bytes.ptr)))[0..array.len];
                    @memcpy(dst_array, array);

                    const len: u32 = @intCast(set.value_table.items.len - start_index);
                    gop.value_ptr.* = .{ .double_array = .{ .idx = start_index, .len = len } };
                },
                .integer_array => |array| {
                    try set.value_table.resize(allocator, std.mem.alignForward(usize, set.value_table.items.len, 8));

                    const start_index: u32 = @intCast(set.value_table.items.len);
                    const table_bytes = try set.value_table.addManyAsSlice(allocator, array.len * 8);
                    const dst_array = @as([*]i64, @ptrCast(@alignCast(table_bytes.ptr)))[0..array.len];
                    @memcpy(dst_array, array);

                    const len: u32 = @intCast(set.value_table.items.len - start_index);
                    gop.value_ptr.* = .{ .integer_array = .{ .idx = start_index, .len = len } };
                },
            }
        }
        return set;
    }

    const StringTableContext = struct {
        string_table: []const u8,

        pub const hashString = std.array_hash_map.hashString;

        pub fn eql(this: @This(), a: Key, b: Key, b_index: usize) bool {
            _ = this;
            _ = b_index;
            return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
        }

        pub fn hash(this: @This(), key: Key) u32 {
            const key_str = switch (key.type) {
                .standard => @tagName(key.data.standard),
                .custom => std.mem.span(@as([*:0]const u8, @ptrCast(this.string_table[@intFromEnum(key.data.custom)..].ptr))),
            };
            return hashString(key_str);
        }
    };

    const StringTableAdapter = struct {
        string_table: []const u8,

        pub const hashString = std.array_hash_map.hashString;

        pub fn eql(this: @This(), a_str: []const u8, b: Key, b_index: usize) bool {
            _ = b_index;
            const b_str = switch (b.type) {
                .standard => @tagName(b.data.standard),
                .custom => std.mem.span(@as([*:0]const u8, @ptrCast(this.string_table[@intFromEnum(b.data.custom)..].ptr))),
            };
            return std.mem.eql(u8, a_str, b_str);
        }

        pub fn hash(this: @This(), key_str: []const u8) u32 {
            _ = this;
            return hashString(key_str);
        }
    };

    pub const Key = packed struct(u32) {
        type: Key.Type,
        data: Data,

        pub const Type = enum(u1) { standard, custom };

        pub const Data = packed union {
            standard: Standard.Name,
            custom: StringIndex,
        };

        pub const StringIndex = enum(u31) { _ };
    };

    pub const Value = union(Type) {
        // ------ primitive types ------

        /// A single string. Strings should not contain nul bytes.
        string: Array,
        boolean: bool,
        double: f64,
        integer: i64,

        // --- primitive array types ---

        /// each string separated by a 0
        string_array: Array,
        /// each byte represents a boolean
        boolean_array: Array,
        /// Offset must be aligned to 8. Every 8 bytes represents a 64-bit float.
        double_array: Array,
        /// Offset must be aligned to 8. Every 8 bytes represents a 64-bit integer.
        integer_array: Array,

        pub const Array = extern struct {
            /// The offset into `value_table`
            idx: u32,
            /// Number of bytes in the value's array. How the type is encoded depends on the
            /// value's type.
            len: u32,
        };
    };

    pub fn getKeyString(this: @This(), key: Key) []const u8 {
        return switch (key.type) {
            .standard => @tagName(key.data.standard),
            .custom => std.mem.span(@as([*:0]const u8, @ptrCast(this.string_table.items[@intFromEnum(key.data.custom)..].ptr))),
        };
    }

    pub fn getValueBytes(this: @This(), array: Set.Value.Array) []const u8 {
        return this.value_table.items[array.idx..][0..array.len];
    }

    pub fn format(this: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("{");
        for (this.kv.keys(), this.kv.values()) |key, val| {
            try writer.writeAll(" ");
            try writer.writeAll(this.getKeyString(key));
            try writer.writeAll("=");

            switch (val) {
                .string => |s| try writer.print("\"{}\"", .{std.zig.fmtEscapes(this.getValueBytes(s))}),
                .boolean => |b| try writer.print("{}", .{b}),
                .double => |d| try writer.print("{e}", .{d}),
                .integer => |i| try writer.print("{}", .{i}),

                .string_array => |array| {
                    var string_iter = std.mem.splitScalar(u8, this.getValueBytes(array), 0);
                    try writer.writeAll("{");
                    while (string_iter.next()) |string| {
                        try writer.print(" \"{}\"", .{std.zig.fmtEscapes(string)});
                    }
                    try writer.writeAll(" }");
                },
                .boolean_array => |array| {
                    try writer.writeAll("{");
                    for (this.getValueBytes(array)) |byte| {
                        try writer.print(" {}", .{byte != 0});
                    }
                    try writer.writeAll(" }");
                },
                .double_array => |array| {
                    const bytes = this.getValueBytes(array);
                    try writer.writeAll("{");
                    for (std.mem.bytesAsSlice(f64, bytes)) |double| {
                        try writer.print(" {e}", .{double});
                    }
                    try writer.writeAll(" }");
                },
                .integer_array => |array| {
                    const bytes = this.getValueBytes(array);
                    try writer.writeAll("{");
                    for (std.mem.bytesAsSlice(i64, bytes)) |integer| {
                        try writer.print(" {d}", .{integer});
                    }
                    try writer.writeAll(" }");
                },
            }
        }
        try writer.writeAll(" }");
    }

    pub fn jsonStringify(this: @This(), jw: anytype) !void {
        try jw.beginArray();
        for (this.kv.keys(), this.kv.values()) |key, val| {
            try jw.beginObject();
            try jw.objectField("key");
            try jw.write(this.getKeyString(key));

            try jw.objectField("value");
            try jw.beginObject();
            switch (val) {
                .string => |array| {
                    try jw.objectField("stringValue");
                    try jw.write(this.getValueBytes(array));
                },
                .boolean => |b| {
                    try jw.objectField("boolValue");
                    try jw.write(b);
                },
                .double => |d| {
                    try jw.objectField("doubleValue");
                    try jw.write(d);
                },
                .integer => |i| {
                    try jw.objectField("intValue");
                    try jw.write(i);
                },
                .string_array => |array| {
                    try jw.objectField("arrayValue");
                    try jw.beginObject();
                    try jw.objectField("values");
                    try jw.beginArray();

                    var string_iter = std.mem.splitScalar(u8, this.getValueBytes(array), 0);
                    while (string_iter.next()) |string| {
                        try jw.beginObject();
                        try jw.objectField("stringValue");
                        try jw.write(string);
                        try jw.endObject();
                    }

                    try jw.endArray();
                    try jw.endObject();
                },
                .boolean_array => |array| {
                    try jw.objectField("arrayValue");
                    try jw.beginObject();
                    try jw.objectField("values");
                    try jw.beginArray();
                    for (this.getValueBytes(array)) |byte| {
                        try jw.beginObject();
                        try jw.objectField("boolValue");
                        try jw.write(byte != 0);
                        try jw.endObject();
                    }
                    try jw.endArray();
                    try jw.endObject();
                },
                .double_array => |array| {
                    try jw.objectField("arrayValue");
                    try jw.beginObject();
                    try jw.objectField("values");
                    try jw.beginArray();

                    const bytes = this.getValueBytes(array);
                    for (std.mem.bytesAsSlice(f64, bytes)) |double| {
                        try jw.beginObject();
                        try jw.objectField("doubleValue");
                        try jw.write(double);
                        try jw.endObject();
                    }

                    try jw.endArray();
                    try jw.endObject();
                },
                .integer_array => |array| {
                    try jw.objectField("arrayValue");
                    try jw.beginObject();
                    try jw.objectField("values");
                    try jw.beginArray();

                    const bytes = this.getValueBytes(array);
                    for (std.mem.bytesAsSlice(i64, bytes)) |double| {
                        try jw.beginObject();
                        try jw.objectField("intValue");
                        try jw.write(double);
                        try jw.endObject();
                    }

                    try jw.endArray();
                    try jw.endObject();
                },
            }
            try jw.endObject();
            try jw.endObject();
        }
        try jw.endArray();
    }
};

const builtin = @import("builtin");
const std = @import("std");
