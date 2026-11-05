package com.example.ransom_calendar

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/// Location via android.location.LocationManager (no wrapper package):
/// - getCurrentAddress returns a human-readable address for the phone's
///   current position, or an error the Dart side surfaces.
/// - Permissions (ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION) are
///   requested at runtime; the Dart side triggers the prompt by
///   calling getCurrentAddress, and a denial returns PERMISSION_DENIED.
class MainActivity : FlutterActivity() {
    private val channelName = "com.case10.ransomcalendar/location"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            if (call.method == "getCurrentAddress") {
                pendingResult = result
                fetchAddress()
            } else {
                result.notImplemented()
            }
        }
    }

    private fun fetchAddress() {
        val result = pendingResult ?: return
        val fine = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                1001
            )
            // The result comes back in onRequestPermissionsResult.
            return
        }
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val loc = lastKnown(lm)
        if (loc != null) {
            result.success(reverseGeocode(loc))
            pendingResult = null
        } else {
            requestSingleUpdate(lm, result)
        }
    }

    @Suppress("MissingPermission")
    private fun lastKnown(lm: LocationManager): Location? {
        // Permissions already checked in fetchAddress.
        val providers = lm.getProviders(true)
        for (provider in listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER
        ) + providers) {
            try {
                lm.getLastKnownLocation(provider)?.let { return it }
            } catch (_: SecurityException) {
                // Provider needs a permission we don't have; skip it.
            }
        }
        return null
    }

    @Suppress("MissingPermission")
    private fun requestSingleUpdate(lm: LocationManager, result: MethodChannel.Result) {
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                lm.removeUpdates(this)
                result.success(reverseGeocode(location))
                pendingResult = null
            }
            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        try {
            val provider = if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                LocationManager.GPS_PROVIDER
            } else {
                LocationManager.NETWORK_PROVIDER
            }
            lm.requestSingleUpdate(provider, listener, Looper.getMainLooper())
            // Give up after 10s rather than hanging the sheet.
            android.os.Handler(Looper.getMainLooper()).postDelayed({
                if (pendingResult != null) {
                    try { lm.removeUpdates(listener) } catch (_: Exception) {}
                    result.error("TIMEOUT", "No location fix within 10s", null)
                    pendingResult = null
                }
            }, 10_000)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message, null)
            pendingResult = null
        } catch (e: IllegalArgumentException) {
            result.error("NO_PROVIDER", e.message, null)
            pendingResult = null
        }
    }

    private fun reverseGeocode(loc: Location): String {
        return try {
            @Suppress("DEPRECATION")
            val addresses = Geocoder(this, Locale.getDefault())
                .getFromLocation(loc.latitude, loc.longitude, 1)
            val a = addresses?.firstOrNull()
            if (a == null) {
                // No address — return raw coords so the field isn't empty.
                "%.5f, %.5f".format(loc.latitude, loc.longitude)
            } else {
                // "123 Main St, Toronto" — street first, then city.
                listOfNotNull(
                    a.thoroughfare?.let { t ->
                        (a.subThoroughfare?.let { "$it " } ?: "") + t
                    },
                    a.locality,
                    a.adminArea
                ).joinToString(", ")
            }
        } catch (e: Exception) {
            "%.5f, %.5f".format(loc.latitude, loc.longitude)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 1001) return
        val result = pendingResult ?: return
        if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
            fetchAddress()
        } else {
            result.error("PERMISSION_DENIED", "Location permission denied", null)
            pendingResult = null
        }
    }
}
