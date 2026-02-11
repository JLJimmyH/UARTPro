cmake_minimum_required(VERSION 3.16)

project(UARTPro VERSION 0.1 LANGUAGES CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.2 COMPONENTS Quick QuickControls2 SerialPort QuickDialogs2 REQUIRED)

qt_add_executable(appUARTPro
    main.cpp
    SerialPortManager.h
    SerialPortManager.cpp
    FileLogger.h
    FileLogger.cpp
)

qt_add_qml_module(appUARTPro
    URI UARTPro
    VERSION 1.0
    QML_FILES
        main.qml
        CyberButton.qml
        CyberComboBox.qml
        CyberCheckBox.qml
        CyberTextField.qml
)

set_target_properties(appUARTPro PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appUARTPro
    PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::SerialPort Qt6::QuickDialogs2)

include(GNUInstallDirs)
install(TARGETS appUARTPro
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})
