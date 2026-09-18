cmake_minimum_required(VERSION 3.16)

# macOS 部署目標必須在 project() 之前設定才會生效。
# Qt 6.7 官方 binary 的最低支援是 macOS 12;CI 可用 -DCMAKE_OSX_DEPLOYMENT_TARGET 覆寫。
if(APPLE AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0" CACHE STRING "Minimum macOS version")
endif()

project(UARTPro LANGUAGES CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# version.h 是版本號的單一來源(RC 資源 / C++ / QML),macOS bundle 的 Info.plist 也由此取值
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/version.h" _version_header)
string(REGEX MATCH "APP_VERSION_STR[ \t]+\"([0-9.]+)\"" _ "${_version_header}")
set(APP_VERSION "${CMAKE_MATCH_1}")
if(NOT APP_VERSION)
    message(FATAL_ERROR "無法從 version.h 解析 APP_VERSION_STR")
endif()

find_package(Qt6 6.2 COMPONENTS Quick QuickControls2 SerialPort QuickDialogs2 Network REQUIRED)
qt_policy(SET QTP0001 NEW)

qt_add_executable(${PROJECT_NAME}
    main.cpp
    SerialPortManager.h
    SerialPortManager.cpp
    FileLogger.h
    FileLogger.cpp
    ConfigManager.h
    ConfigManager.cpp
    TerminalModel.h
    TerminalModel.cpp
    HeadlessRunner.h
    HeadlessRunner.cpp
    IpcServer.h
    IpcServer.cpp
    AttachClient.h
    AttachClient.cpp
    version.h
)

# app.rc 是 Windows resource script,非 MSVC 平台的編譯器不認得
if(WIN32)
    target_sources(${PROJECT_NAME} PRIVATE app.rc)
endif()

qt_add_qml_module(${PROJECT_NAME}
    URI UARTPro
    VERSION 1.0
    QML_FILES
        main.qml
        CyberButton.qml
        CyberComboBox.qml
        CyberCheckBox.qml
        CyberTextField.qml
        EyeIcon.qml
        BroomIcon.qml
        FolderIcon.qml
)

set_target_properties(${PROJECT_NAME} PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
)

if(APPLE)
    set_target_properties(${PROJECT_NAME} PROPERTIES
        MACOSX_BUNDLE_BUNDLE_NAME "UARTPro"
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.jeilin.uartpro"
        MACOSX_BUNDLE_BUNDLE_VERSION "${APP_VERSION}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${APP_VERSION}"
        MACOSX_BUNDLE_COPYRIGHT "Jeilin Semiconductor"
    )
endif()

target_link_libraries(${PROJECT_NAME}
    PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::SerialPort Qt6::QuickDialogs2 Qt6::Network)
