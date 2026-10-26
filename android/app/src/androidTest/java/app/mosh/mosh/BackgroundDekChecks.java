package app.mosh.mosh;

import android.content.Context;
import android.security.keystore.KeyInfo;
import java.io.File;
import java.nio.file.Files;
import java.security.KeyStore;
import java.util.Arrays;
import javax.crypto.SecretKey;
import javax.crypto.SecretKeyFactory;

/** Real Keystore/file checks; invoke only in the disposable instrumentation app. */
public final class BackgroundDekChecks {
    private static final String ALIAS = "app.mosh.mobile.background-dek.v1";

    public static void run(Context context) throws Exception {
        require(context.getPackageName().endsWith(".linked_dm_test"),
            "Key fault tests require the isolated linked_dm_test application ID");
        File envelope = new File(context.getNoBackupFilesDir(), "background-dek-v1");
        require(!envelope.exists(), "Use a fresh disposable test installation for key checks");
        KeyStore keys = KeyStore.getInstance("AndroidKeyStore");
        keys.load(null);
        require(!keys.containsAlias(ALIAS), "Use a fresh disposable test installation for key checks");
        try {
            checkStore(context, envelope, keys);
        } finally {
            // These belong only to this fresh, explicitly isolated test UID.
            for (String suffix : new String[] {"", ".new", ".bak"}) {
                File owned = new File(envelope.getPath() + suffix);
                require(!owned.exists() || owned.delete(), "Could not remove isolated test envelope");
            }
            keys.deleteEntry(ALIAS);
        }
    }

    private static void checkStore(Context context, File envelope, KeyStore keys) throws Exception {
        byte[] original = new byte[32];
        Arrays.fill(original, (byte) 91);
        MoshBackgroundDek storage = new MoshBackgroundDek(context);
        require(storage.read() == null, "Unexpected preexisting wrapping");
        storage.install(original);
        checkWrappingPolicy(keys);
        require(Arrays.equals(original, new MoshBackgroundDek(context).read()),
            "A new owner could not reopen the same committed DEK");
        storage.install(original);
        byte[] different = new byte[32];
        expectCode("DEK_CONFLICT", () -> storage.install(different));
        require(Arrays.equals(original, storage.read()), "Refused install changed the DEK");
        byte[] encoded = Files.readAllBytes(envelope.toPath());
        require(encoded.length == 64, "Invalid envelope size");
        encoded[63] ^= 1;
        Files.write(envelope.toPath(), encoded);
        expectCode("DEK_ENVELOPE_INVALID", storage::read);
        expectCode("DEK_ENVELOPE_INVALID", () -> storage.install(original));
        // Storage repair is exercised directly; channel authentication is a
        // separate Activity test. This does not claim biometric acceptance.
        storage.recover(original);
        require(Arrays.equals(original, storage.read()), "Repair changed the legacy DEK");
        keys.deleteEntry(ALIAS);
        expectCode("DEK_KEY_MISSING", storage::read);
        expectCode("DEK_KEY_MISSING", () -> storage.install(original));
        require(!keys.containsAlias(ALIAS), "Ordinary access regenerated a missing alias");
        storage.recover(original);
        require(Arrays.equals(original, storage.read()), "Missing-alias repair changed the DEK");
        encoded = Files.readAllBytes(envelope.toPath());
        encoded[3] = '2';
        Files.write(envelope.toPath(), encoded);
        expectCode("DEK_ENVELOPE_VERSION", storage::read);
        expectCode("DEK_ENVELOPE_VERSION", () -> storage.recover(original));
    }

    private static void checkWrappingPolicy(KeyStore keys) throws Exception {
        SecretKeyFactory factory = SecretKeyFactory.getInstance("AES", "AndroidKeyStore");
        KeyInfo info = (KeyInfo) factory.getKeySpec((SecretKey) keys.getKey(ALIAS, null), KeyInfo.class);
        require(!info.isUserAuthenticationRequired(), "Background wrapping still requires per-use authentication");
        require(info.getKeySize() == 256, "Unexpected wrapping key strength");
    }

    private static void expectCode(String expected, Runnable action) {
        try {
            action.run();
            throw new AssertionError("Unsafe key operation was accepted");
        } catch (BackgroundDekException error) {
            require(expected.equals(error.getCode()), "Unexpected sanitized key error code");
        }
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
