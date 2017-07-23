set (NAME feedbin)

set (UINAME ${NAME}UI)
set (DAEMONTARGET ${NAME}_target)
set (UITARGET ${UINAME}_target)
set (TEST_NAME test_${NAME})

# ----------------------------------------------------------
# Daemon Plugin
# ----------------------------------------------------------

vala_precompile(VALA_C ${DAEMONTARGET}
    feedbinInterface.vala
    feedbinAPI.vala
    feedbinConnection.vala
    feedbinUtils.vala

PACKAGES
    libpeas-1.0
    json-glib-1.0
    libsoup-2.4
    gee-0.8
    libxml-2.0
    sqlite3
    libsecret-1

OPTIONS
    --target-glib=2.32
    --library ${NAME}

CUSTOM_VAPIS
    ${CMAKE_BINARY_DIR}/FeedReader.vapi
    ${CMAKE_BINARY_DIR}/FeedReaderCommon.vapi
)

add_library(${NAME} SHARED ${VALA_C})
target_link_libraries(${NAME} FeedReaderCommon)


# ----------------------------------------------------------
# UI Plugin
# ----------------------------------------------------------


vala_precompile(VALA_C2 ${UITARGET}
    feedbinLoginWidget.vala
    feedbinUtils.vala

PACKAGES
    libpeas-1.0
    gtk+-3.0
    gee-0.8
    libsecret-1
    sqlite3
    libsoup-2.4
    WebKit2-4.0
    libxml-2.0

OPTIONS
    --target-glib=2.32
    --library ${NAME}

CUSTOM_VAPIS
    ${CMAKE_BINARY_DIR}/FeedReaderUI.vapi
    ${CMAKE_BINARY_DIR}/FeedReaderCommon.vapi
    ${CMAKE_SOURCE_DIR}/vapi/gd-1.0.vapi
)

GLIB_COMPILE_RESOURCES(GRESOURCES SOURCE ${NAME}.gresource.xml)

add_library(${UINAME} SHARED ${VALA_C2} ${GRESOURCES})

# ----------------------------------------------------------
# Tests
# ----------------------------------------------------------

vala_precompile(VALA_C ${TEST_NAME}
    feedbinAPI.vala
    feedbinConnection.vala
    feedbinUtils.vala
    TestFeedbinAPI.vala

PACKAGES
    json-glib-1.0
    libsoup-2.4
    gee-0.8
    libxml-2.0
    libsecret-1
    sqlite3

OPTIONS
    --target-glib=2.32
    --library ${NAME}

CUSTOM_VAPIS
    ${CMAKE_BINARY_DIR}/FeedReaderCommon.vapi
)

add_executable(${TEST_NAME} ${VALA_C})
target_link_libraries(${TEST_NAME} FeedReaderCommon)

# ----------------------------------------------------------

add_dependencies(${NAME} ${UI_NAME} ${DAEMON_NAME})
add_dependencies(${UINAME} ${UI_NAME} ${DAEMON_NAME})


add_schema("org.gnome.feedreader.${NAME}.gschema.xml")

install(TARGETS ${NAME} DESTINATION ${PKGLIBDIR}/plugins)
install(TARGETS ${UINAME} DESTINATION ${PKGLIBDIR}/pluginsUI)
install(FILES ${NAME}.plugin DESTINATION ${PKGLIBDIR}/plugins)
install(FILES ${UINAME}.plugin DESTINATION ${PKGLIBDIR}/pluginsUI)
