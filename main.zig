// main.zig
//
// This file serves as the main entry point for the Zig Cache server.
// It will house the core logic for initializing the server,
// listening for connections, and handling cache operations.

const std = @import("std");
const testing = std.testing; // Added for tests
const Allocator = std.mem.Allocator;
const HashMap = std.StringHashMap; // Alias for HashMap with []const u8 keys

// Global allocator instance
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator(); // Get an Allocator interface

// The global cache instance
// We'll store []const u8 for both keys and values.
// For simplicity, we'll assume keys and values are UTF-8 strings.
// Memory management for these strings will need careful consideration.
// Initially, we might copy them into memory managed by this HashMap.
var cache: HashMap([]const u8) = undefined;

pub fn main() !void {
    // Initialize the cache
    cache = HashMap([]const u8).init(allocator);
    std.debug.print("Cache initialized.\n", .{});

    // TODO: Implement server startup logic
    // TODO: Implement request handling

    // Deinitialize and free resources when done (important for GPA)
    // This part might be more complex in a real server application
    // that runs indefinitely.
    // Conditional defer for deinitialization: only if not in test build.
    // The test runner will manage the gpa deinitialization for the test execution scope.
    if (!testing.is_test_build) {
        defer {
            // Iterate and free keys and values if they were duplicated
            var it = cache.iterator();
            while (it.next()) |entry| {
                // Free the duplicated key and value
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            cache.deinit(); // Deinitialize the HashMap itself
            const deinit_status = gpa.deinit(); // Deinitialize the GeneralPurposeAllocator
            if (deinit_status == .leak) {
                std.debug.print("GPA deinit reported a leak!\n", .{}); // Should not happen with proper freeing
            }
            std.debug.print("Cache deinitialized.\n", .{});
        }
    }

    // Example usage (to be replaced by actual server logic and tests)
    // This part will run for `zig run main.zig`.
    // For `zig test main.zig`, main() is run, then tests are run.
    // We don't want this example logic to interfere with test state if main() runs before tests.
    // However, tests already call clearAndFree(), so it might be okay.
    // To be safe, only run example logic if not in test build.
    if (!testing.is_test_build) {
        try set("hello", "world");
        try set("another", "entry");
        try set("hello", "new_world"); // Overwrite existing key

        if (get("hello")) |value| { // Removed 'try'
            std.debug.print("Main Got: {s} = {s}\n", .{"hello", value});
        } else {
            std.debug.print("Main Got: hello = null\n", .{});
        }
        if (get("another")) |value| { // Removed 'try'
            std.debug.print("Main Got: {s} = {s}\n", .{"another", value});
        } else {
            std.debug.print("Main Got: another = null\n", .{});
        }
        if (get("unknown")) |value| { // Test non-existent key
            std.debug.print("Main Got: {s} = {s}\n", .{"unknown", value});
        } else {
            std.debug.print("Main Got: unknown = null\n", .{});
        }

        // Test delete
        std.debug.print("Deleting 'hello': {}\n", .{delete("hello")});
        if (get("hello")) |value| {
            std.debug.print("Main Got after delete hello: {s} = {s}\n", .{"hello", value});
        } else {
            std.debug.print("Main Got after delete hello: hello = null\n", .{});
        }

        std.debug.print("Deleting 'another': {}\n", .{delete("another")});
        if (get("another")) |value| {
            std.debug.print("Main Got after delete another: {s} = {s}\n", .{"another", value});
        } else {
            std.debug.print("Main Got after delete another: another = null\n", .{});
        }

        std.debug.print("Deleting 'non_existent_key': {}\n", .{delete("non_existent_key")});
    }
}

// Set function for the cache
pub fn set(key: []const u8, value: []const u8) !void {
    // Duplicate the key and value to ensure the cache owns them.
    // These allocations are owned by the function until successfully put into the map.
    const key_copy = try allocator.dupe(u8, key);
    // If value allocation fails or put fails later, key_copy must be freed.
    errdefer allocator.free(key_copy);

    const value_copy = try allocator.dupe(u8, value);
    // If put fails, value_copy must be freed. key_copy is handled by the errdefer above.
    errdefer allocator.free(value_copy);

    // Try to put the new key and value into the cache.
    // `put` will return the previous value if the key already existed.
    const prev_entry = try cache.fetchPut(key_copy, value_copy);

    if (prev_entry) |old_entry| {
        // Key already existed.
        // The key_copy we just made was NOT inserted because the key was already there.
        // The map keeps its original key. So, free our key_copy.
        allocator.free(key_copy);
        // The value_copy IS inserted, replacing old_entry.value.
        // We need to free the old_entry.value that was replaced.
        allocator.free(old_entry.value);
        // old_entry.key should not be freed here as it's the key stored in the map.
        std.debug.print("SET (updated): {s} = {s}\n", .{key, value});
    } else {
        // New key was inserted.
        // key_copy and value_copy are now owned by the HashMap.
        // No need to free them here.
        std.debug.print("SET (new): {s} = {s}\n", .{key, value});
    }
}

// Placeholder for get function
pub fn get(key: []const u8) ?[]const u8 {
    if (cache.get(key)) |value| {
        std.debug.print("GET: {s} = {s}\n", .{key, value});
        return value;
    } else {
        std.debug.print("GET: {s} = null\n", .{key});
        return null;
    }
}

// Delete function for the cache
pub fn delete(key: []const u8) bool {
    if (cache.fetchRemove(key)) |removed_entry| {
        // Key was found and removed.
        // The removed_entry contains the key and value that were in the map.
        allocator.free(removed_entry.key);
        allocator.free(removed_entry.value);
        std.debug.print("DELETE: {s} - success\n", .{key});
        return true;
    } else {
        // Key was not found, fetchRemove returned null.
        std.debug.print("DELETE: {s} - not found\n", .{key});
        return false;
    }
}

// TODO: Define data structures for cache storage - This is being addressed now.

// --- Unit Tests ---

test "set and get basic" {
    // Initialize cache for this test and ensure deinitialization
    cache = HashMap([]const u8).init(allocator);
    defer cache.deinit(); // This will free all entries using the map's allocator

    try set("key1", "value1");
    const value = get("key1");
    try testing.expect(value != null);
    try testing.expect(std.mem.eql(u8, value.?, "value1"));
}

test "set and update value" {
    cache = HashMap([]const u8).init(allocator);
    defer cache.deinit();

    try set("key_update", "initial_value");
    var value = get("key_update");
    try testing.expect(value != null);
    try testing.expect(std.mem.eql(u8, value.?, "initial_value"));

    try set("key_update", "updated_value");
    value = get("key_update");
    try testing.expect(value != null);
    try testing.expect(std.mem.eql(u8, value.?, "updated_value"));
}

test "get non-existent key" {
    cache = HashMap([]const u8).init(allocator);
    defer cache.deinit();

    const value = get("non_existent_key");
    try testing.expect(value == null);
}

test "set, delete, and get key" {
    cache = HashMap([]const u8).init(allocator);
    defer cache.deinit();

    try set("key_del", "value_del");
    var value = get("key_del");
    try testing.expect(value != null); // Ensure it's there first
    try testing.expect(std.mem.eql(u8, value.?, "value_del"));

    const deleted = delete("key_del");
    try testing.expect(deleted);

    value = get("key_del");
    try testing.expect(value == null); // Should be null after delete
}

test "delete non-existent key" {
    cache = HashMap([]const u8).init(allocator);
    defer cache.deinit();

    const deleted = delete("non_existent_delete");
    try testing.expect(!deleted); // Should return false
}

test "set multiple, delete one, check others" {
    cache = HashMap([]const u8).init(allocator);
    defer cache.deinit();

    try set("multi1", "val1");
    try set("multi2", "val2");
    try set("multi3", "val3");

    // Delete one key
    const deleted = delete("multi2");
    try testing.expect(deleted);

    // Check that multi2 is gone
    var value = get("multi2");
    try testing.expect(value == null);

    // Check that multi1 is still there
    value = get("multi1");
    try testing.expect(value != null);
    try testing.expect(std.mem.eql(u8, value.?, "val1"));

    // Check that multi3 is still there
    value = get("multi3");
    try testing.expect(value != null);
    try testing.expect(std.mem.eql(u8, value.?, "val3"));
}

test "overwrite existing key and ensure old value freed (implicit)" {
    // This test relies on the GPA leak detection in main's defer block
    // if run via `zig run main.zig` after tests, or if GPA state persists across tests.
    // For `zig test`, the global GPA is deinitialized once after all tests.
    // If `set` doesn't free the old value, GPA would report a leak.
    cache = HashMap([]const u8).init(allocator);
    defer cache.deinit();

    // Put a string that's somewhat unique in length/content to help identify leaks if they happen
    const old_value_str = "old_value_to_be_replaced_and_freed";
    const new_value_str = "new_value";

    try set("overwrite_key", old_value_str);
    const old_value_in_map = get("overwrite_key").?; // Assuming it's there
    try testing.expect(std.mem.eql(u8, old_value_in_map, old_value_str));

    try set("overwrite_key", new_value_str); // This should free the old_value_str's copy
    const new_value_in_map = get("overwrite_key").?;
    try testing.expect(std.mem.eql(u8, new_value_in_map, new_value_str));

    // No explicit check for freeing here, relying on GPA deinit.
    // To be more explicit, one would need a custom allocator for tracking.
}

test "set and get empty string value" {
    cache = HashMap([]const u8).init(allocator);
    defer cache.deinit();
    try set("empty_value_key", "");
    const value = get("empty_value_key");
    try testing.expect(value != null);
    try testing.expect(std.mem.eql(u8, value.?, ""));
}

test "set and get empty string key" {
    // StringHashMap allows empty string keys
    cache = HashMap([]const u8).init(allocator);
    defer cache.deinit();
    try set("", "empty_key_value");
    const value = get("");
    try testing.expect(value != null);
    try testing.expect(std.mem.eql(u8, value.?, "empty_key_value"));
}
