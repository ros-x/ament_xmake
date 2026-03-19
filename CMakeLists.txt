cmake_minimum_required(VERSION 3.16)
project(ament_xmake)

find_package(ament_cmake REQUIRED)

install(DIRECTORY xmake/
  DESTINATION share/${PROJECT_NAME}/xmake)

install(DIRECTORY cmake/
  DESTINATION share/${PROJECT_NAME}/cmake)

install(FILES package.xml
  DESTINATION share/${PROJECT_NAME})

ament_package()
