cmake_minimum_required(VERSION 3.16)

project(UARTPro VERSION 0.1 LANGUAGES CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.2 COMPONENTS Quick QuickControls2 SerialPort QuickDialogs2 REQUIRED)
qt_policy(SET QTP0001 NEW)

qt_add_executable(${PROJECT_NAME}
    main.cpp
    SerialPortManager.h
    SerialPortManager.cpp
    FileLogger.h
    FileLogger.cpp
    ConfigManager.h
    ConfigManager.cpp
    app.rc
)

qt_add_qml_module(${PROJECT_NAME}
    URI UARTPro
    VERSION 1.0
    QML_FILES
        main.qml
        CyberButton.qml
        CyberComboBox.qml
        CyberCheckBox.qml
        CyberTextField.qml
)

set_target_properties(${PROJECT_NAME} PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(${PROJECT_NAME}
    PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::SerialPort Qt6::QuickDialogs2)

include(GNUInstallDirs)
install(TARGETS ${PROJECT_NAME}
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})
