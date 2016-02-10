package io.joram.notiflier;

public class Constants {

    public enum RegistrationStatus {
        NONE,
        STARTED,
        COMPLETE,
        FAILED
    }

    // Used both as an intent action name and preference name
    public static final String REGISTRATION_STATUS = "RegistrationStatus";

    // Intent extra names
    public static final String ERROR_MESSAGE = "ErrorMessage";

    // Preference names (also REGISTRATION_STATUS)
    public static final String SERVER_URL = "ServerUrl";
    public static final String NAME = "Name";
    public static final String TOKEN = "Token";
}
