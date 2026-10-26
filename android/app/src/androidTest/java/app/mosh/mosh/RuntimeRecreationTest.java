package app.mosh.mosh;

import android.app.Activity;
import android.app.Application;
import android.app.Instrumentation;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import io.flutter.embedding.engine.FlutterEngine;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/** Actual Activity/engine regression, using only the Android instrumentation API. */
public final class RuntimeRecreationTest extends Instrumentation {
    private final ArrayBlockingQueue<MainActivity> resumed = new ArrayBlockingQueue<>(4);
    private boolean checkBackgroundDek;
    private boolean checkAccessExpiry;

    @Override
    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        checkBackgroundDek = arguments != null && "true".equals(arguments.getString("backgroundDek"));
        checkAccessExpiry = arguments != null && "true".equals(arguments.getString("accessExpiry"));
        start();
    }

    @Override
    public void onStart() {
        Bundle status = new Bundle();
        status.putString("class", getClass().getName());
        status.putString("test", "keepsRunningDartAcrossActivityRecreation");
        status.putInt("current", 1);
        status.putInt("numtests", 1);
        sendStatus(1, status);
        try {
            if (checkBackgroundDek) BackgroundDekChecks.run(getTargetContext());
            checkRecreation();
            sendStatus(0, status);
        } catch (Throwable error) {
            status.putString("stack", Log.getStackTraceString(error));
            sendStatus(-2, status);
        }
        finish(Activity.RESULT_OK, new Bundle());
    }

    private void checkRecreation() throws Exception {
        Application application = (Application) getTargetContext().getApplicationContext();
        Application.ActivityLifecycleCallbacks observer = observer();
        application.registerActivityLifecycleCallbacks(observer);
        MainActivity current = null;
        try {
            Intent intent = new Intent(getTargetContext(), MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            current = (MainActivity) startActivitySync(intent);
            waitForIdleSync();
            if (checkAccessExpiry) AccessExpiryChecks.run(this, current);
            resumed.clear();
            AtomicReference<FlutterEngine> retained = new AtomicReference<>();
            MainActivity first = current;
            runOnMainSync(() -> retained.set(first.provideFlutterEngine(first)));
            FlutterEngine engine = retained.get();
            require(engine != null, "The Activity must expose its application-owned engine");
            require(engine.getDartExecutor().isExecutingDart(), "Dart was not started");
            AtomicBoolean destroyed = new AtomicBoolean();
            runOnMainSync(() -> engine.addEngineLifecycleListener(new FlutterEngine.EngineLifecycleListener() {
                @Override public void onPreEngineRestart() { destroyed.set(true); }
                @Override public void onEngineWillDestroy() { destroyed.set(true); }
            }));
            for (int attempt = 0; attempt < 3; attempt++) {
                MainActivity previous = current;
                runOnMainSync(previous::recreate);
                current = resumed.poll(15, TimeUnit.SECONDS);
                require(current != null && current != previous, "No replacement Activity resumed");
                MainActivity replacement = current;
                runOnMainSync(() -> retained.set(replacement.provideFlutterEngine(replacement)));
                require(retained.get() == engine, "Recreation replaced the engine and its Dart owners");
                require(!destroyed.get(), "Recreation restarted or destroyed Dart");
                require(engine.getDartExecutor().isExecutingDart(), "Dart stopped on recreation");
            }
        } finally {
            application.unregisterActivityLifecycleCallbacks(observer);
            if (current != null) {
                MainActivity last = current;
                runOnMainSync(last::finish);
            }
        }
    }

    private Application.ActivityLifecycleCallbacks observer() {
        return new Application.ActivityLifecycleCallbacks() {
            @Override public void onActivityResumed(Activity activity) {
                if (activity instanceof MainActivity) resumed.offer((MainActivity) activity);
            }
            @Override public void onActivityCreated(Activity activity, Bundle state) { }
            @Override public void onActivityStarted(Activity activity) { }
            @Override public void onActivityPaused(Activity activity) { }
            @Override public void onActivityStopped(Activity activity) { }
            @Override public void onActivitySaveInstanceState(Activity activity, Bundle state) { }
            @Override public void onActivityDestroyed(Activity activity) { }
        };
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
