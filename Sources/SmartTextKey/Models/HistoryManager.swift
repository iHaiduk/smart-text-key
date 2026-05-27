import Foundation
import SQLite3

@MainActor
public final class HistoryManager: HistoryStoreProtocol {
    public static let shared = HistoryManager()
    
    public private(set) var databaseError: String? = nil
    private var db: OpaquePointer?
    private var customDbPath: String?
    
    private init() {
        setupDatabase()
    }
    
    /// Switches the database to a custom location (e.g. ":memory:" or a temporary path for testing).
    public func useDatabase(at path: String) {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
        self.customDbPath = path
        self.databaseError = nil
        setupDatabase()
    }
    
    private func setupDatabase() {
        let dbPath: String
        
        if let custom = customDbPath {
            dbPath = custom
        } else {
            guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                let errorMsg = "Failed to get Application Support directory."
                AppLogger.history.error("\(errorMsg)")
                self.databaseError = errorMsg
                return
            }
            
            let dbDirectory = appSupportURL.appendingPathComponent("SmartTextKey")
            do {
                try FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                let errorMsg = "Failed to create database directory: \(error.localizedDescription)"
                AppLogger.history.error("\(errorMsg)")
                self.databaseError = errorMsg
                return
            }
            
            let dbURL = dbDirectory.appendingPathComponent("history.db")
            dbPath = dbURL.path
        }
        
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            AppLogger.history.log("SQLite database opened successfully at \(dbPath)")
            createTable()
        } else {
            let errorMsg = "Failed to open SQLite database at \(dbPath)."
            AppLogger.history.error("\(errorMsg)")
            self.databaseError = errorMsg
            if let db = db {
                sqlite3_close(db)
                self.db = nil
            }
        }
    }
    
    private func createTable() {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS transformations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            prompt_title TEXT NOT NULL,
            input_text TEXT NOT NULL,
            output_text TEXT NOT NULL
        );
        """
        
        var errorPointer: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, createTableSQL, nil, nil, &errorPointer) != SQLITE_OK {
            let errorMsg = errorPointer.map { String(cString: $0) } ?? "Unknown error"
            AppLogger.history.error("Failed to create table: \(errorMsg)")
            self.databaseError = "Failed to create table: \(errorMsg)"
            if let errorPointer = errorPointer {
                sqlite3_free(errorPointer)
            }
        }
        
        let alterTableSQL = "ALTER TABLE transformations ADD COLUMN model_name TEXT;"
        var alterErrorPointer: UnsafeMutablePointer<Int8>?
        let status = sqlite3_exec(db, alterTableSQL, nil, nil, &alterErrorPointer)
        if status != SQLITE_OK {
            let errorMsg = alterErrorPointer.map { String(cString: $0) } ?? "Unknown error"
            if !errorMsg.contains("duplicate column name") {
                AppLogger.history.error("Failed to alter table: \(errorMsg)")
                self.databaseError = "Failed to migrate database schema: \(errorMsg)"
            }
            if let alterErrorPointer = alterErrorPointer {
                sqlite3_free(alterErrorPointer)
            }
        }
    }
    
    public func logTransformation(promptTitle: String, inputText: String, outputText: String, modelName: String) {
        guard let db = db else { return }
        
        let insertSQL = """
        INSERT INTO transformations (timestamp, prompt_title, input_text, output_text, model_name)
        VALUES (?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            let timestamp = Date().timeIntervalSince1970
            
            sqlite3_bind_double(statement, 1, timestamp)
            sqlite3_bind_text(statement, 2, (promptTitle as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (inputText as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (outputText as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (modelName as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                AppLogger.history.log("Successfully logged transformation.")
            } else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                AppLogger.history.error("Failed to insert row: \(errorMsg)")
            }
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            AppLogger.history.error("Failed to prepare insert statement: \(errorMsg)")
        }
        
        sqlite3_finalize(statement)
    }
    
    public func fetchAll() -> [HistoryItem] {
        guard let db = db else { return [] }
        
        let selectSQL = """
        SELECT id, timestamp, prompt_title, input_text, output_text, model_name
        FROM transformations
        ORDER BY timestamp DESC;
        """
        
        var statement: OpaquePointer?
        var items: [HistoryItem] = []
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let timestampVal = sqlite3_column_double(statement, 1)
                
                let promptTitle: String
                if let cPromptTitle = sqlite3_column_text(statement, 2) {
                    promptTitle = String(cString: cPromptTitle)
                } else {
                    promptTitle = ""
                }
                
                let inputText: String
                if let cInputText = sqlite3_column_text(statement, 3) {
                    inputText = String(cString: cInputText)
                } else {
                    inputText = ""
                }
                
                let outputText: String
                if let cOutputText = sqlite3_column_text(statement, 4) {
                    outputText = String(cString: cOutputText)
                } else {
                    outputText = ""
                }
                
                let modelName: String
                if let cModelName = sqlite3_column_text(statement, 5) {
                    modelName = String(cString: cModelName)
                } else {
                    modelName = "Unknown"
                }
                
                let date = Date(timeIntervalSince1970: timestampVal)
                items.append(HistoryItem(
                    id: id,
                    timestamp: date,
                    promptTitle: promptTitle,
                    inputText: inputText,
                    outputText: outputText,
                    modelName: modelName
                ))
            }
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            AppLogger.history.error("Failed to prepare select statement: \(errorMsg)")
        }
        
        sqlite3_finalize(statement)
        return items
    }
    
    public func delete(id: Int64) {
        guard let db = db else { return }
        
        let deleteSQL = "DELETE FROM transformations WHERE id = ?;"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, id)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                AppLogger.history.log("Successfully deleted history item: \(id)")
            } else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                AppLogger.history.error("Failed to delete row: \(errorMsg)")
            }
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            AppLogger.history.error("Failed to prepare delete statement: \(errorMsg)")
        }
        
        sqlite3_finalize(statement)
    }
    
    public func clearAll() {
        guard let db = db else { return }
        
        let clearSQL = "DELETE FROM transformations;"
        
        var errorPointer: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, clearSQL, nil, nil, &errorPointer) == SQLITE_OK {
            AppLogger.history.log("Successfully cleared all transformation history.")
        } else {
            let errorMsg = errorPointer.map { String(cString: $0) } ?? "Unknown error"
            AppLogger.history.error("Failed to clear history: \(errorMsg)")
            if let errorPointer = errorPointer {
                sqlite3_free(errorPointer)
            }
        }
    }
}
