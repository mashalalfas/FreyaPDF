package com.feya.feya_pdf

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.feya.feya_pdf/intent"
    private var initialFilePath: String? = null
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFilePath" -> {
                    result.success(initialFilePath)
                    initialFilePath = null // consumed
                }
                "copyContentUri" -> {
                    val uriString = call.arguments as? String
                    if (uriString != null) {
                        val path = copyContentUriToTemp(Uri.parse(uriString))
                        result.success(path)
                    } else {
                        result.error("INVALID_URI", "URI is null", null)
                    }
                }
                "listContentUriFiles" -> {
                    val uriString = call.arguments as? String
                    if (uriString != null) {
                        try {
                            val files = listPdfFilesRecursive(Uri.parse(uriString))
                            result.success(files)
                        } catch (e: Exception) {
                            result.error("SCAN_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_URI", "URI is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Handle intent on launch
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        val action = intent.action
        val uri: Uri? = intent.data

        if (uri != null && (action == Intent.ACTION_VIEW || action == Intent.ACTION_OPEN_DOCUMENT)) {
            val path = resolveUri(uri)
            if (path != null) {
                // If Flutter is ready, send immediately
                methodChannel?.invokeMethod("openFile", path)
                // Also store for initial retrieval
                initialFilePath = path
            }
        }
    }

    private fun resolveUri(uri: Uri): String? {
        // If it's a file:// URI, return the path directly
        if (uri.scheme == "file") {
            return uri.path
        }

        // If it's a content:// URI, copy to temp
        if (uri.scheme == "content") {
            return copyContentUriToTemp(uri)
        }

        return uri.path
    }

    /**
     * Recursively list all PDF/ENC files under a SAF content URI directory.
     * Each file is copied to the app cache and its cached path is returned.
     * Returns a Map where keys are display names and values are cached file paths.
     */
    private fun listPdfFilesRecursive(uri: Uri): Map<String, String> {
        val result = mutableMapOf<String, String>()
        val tempDir = File(cacheDir, "saf_pdfs")
        tempDir.mkdirs()

        // Build the children URI for this tree/document
        val docId = DocumentsContract.getTreeDocumentId(uri)
            ?: DocumentsContract.getDocumentId(uri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(uri, docId)

        val cursor = contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE
            ),
            null, null, null
        )

        cursor?.use {
            val idIdx = it.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIdx = it.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIdx = it.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)

            while (it.moveToNext()) {
                val childId = it.getString(idIdx)
                val name = it.getString(nameIdx)
                val mimeType = it.getString(mimeIdx)
                val childUri = DocumentsContract.buildDocumentUriUsingTree(uri, childId)

                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR ||
                    mimeType == "vnd.android.document/directory") {
                    // Recurse into subdirectory
                    result.putAll(listPdfFilesRecursive(childUri))
                } else if (name != null && (
                    name.endsWith(".pdf", ignoreCase = true) ||
                    name.endsWith(".pdf.enc", ignoreCase = true)
                )) {
                    // Copy PDF to cache
                    val cachedPath = copyContentUriToTempWithName(childUri, name, tempDir)
                    if (cachedPath != null) {
                        result[name] = cachedPath
                    }
                }
            }
        }

        return result
    }

    /**
     * Copy a content URI to a cache file with a deterministic name.
     * Avoids duplicate copies if the file already exists in cache.
     */
    private fun copyContentUriToTempWithName(uri: Uri, fileName: String, dir: File): String? {
        try {
            val outFile = File(dir, fileName)
            // Skip copy if file exists and has content
            if (outFile.exists() && outFile.length() > 0) {
                return outFile.absolutePath
            }
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val outputStream = FileOutputStream(outFile)
            inputStream.use { input ->
                outputStream.use { output ->
                    input.copyTo(output)
                }
            }
            return outFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }

    private fun copyContentUriToTemp(uri: Uri): String? {
        try {
            val inputStream = contentResolver.openInputStream(uri) ?: return null

            // Get filename from URI
            var fileName = "shared_pdf_${System.currentTimeMillis()}.pdf"
            val cursor = contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val nameIndex = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) {
                        fileName = it.getString(nameIndex) ?: fileName
                    }
                }
            }

            // Ensure .pdf extension
            if (!fileName.endsWith(".pdf", ignoreCase = true)) {
                fileName = "$fileName.pdf"
            }

            val tempDir = File(cacheDir, "shared_pdfs")
            tempDir.mkdirs()
            val tempFile = File(tempDir, fileName)

            val outputStream = FileOutputStream(tempFile)
            inputStream.use { input ->
                outputStream.use { output ->
                    input.copyTo(output)
                }
            }

            return tempFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }
}
