cmake_minimum_required(VERSION 3.16)

project(UARTPro LANGUAGES CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 17)
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
    TerminalModel.h
    TerminalModel.cpp
    HeadlessRunner.h
    HeadlessRunner.cpp
    version.h
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
        EyeIcon.qml
        BroomIcon.qml
        FolderIcon.qml
)

set_target_properties(${PROJECT_NAME} PROPERTIES
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(${PROJECT_NAME}
    PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::SerialPort Qt6::QuickDialogs2)
