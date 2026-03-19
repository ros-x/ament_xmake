cmake_minimum_required(VERSION 3.16)
project(ament_xmake)

find_package(ament_cmake REQUIRED)

install(FILES resource/${PROJECT_NAME}
  DESTINATION share/ament_index/resource_index/packages)

install(DIRECTORY xmake/
  DESTINATION share/${PROJECT_NAME}/xmake)

install(DIRECTORY cmake/
  DESTINATION share/${PROJECT_NAME}/cmake)

install(FILES package.xml
  DESTINATION share/${PROJECT_NAME})

ament_package()
