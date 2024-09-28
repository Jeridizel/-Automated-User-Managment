# Automated User Management

**Automated User Management** is a system designed to streamline and automate user management tasks across various platforms, including BambooHR and other HR or user-related systems. This project automates tasks such as user creation, updating, and deactivation, allowing organizations to maintain accurate employee data with minimal manual intervention.

## Features

- **User Creation**: Automatically creates new users in multiple systems based on provided input data.
- **User Updates**: Keeps user information synchronized across different platforms by updating their details such as name, job title, department, etc.
- **User Deactivation**: Deactivates users upon termination or other triggering events, ensuring proper access management.
- **Customizable**: The system can be extended to include additional platforms as needed.

## How It Works

This project is built using automation scripts (PowerShell) that interact with APIs from various systems to perform the desired operations. The automation reduces the need for manual data entry and ensures that user data is consistent across all platforms.

## Input Data Format

To use the automation scripts, you will need to provide input data in a structured XML format. Below is an example of how the input data should look:

```xml
<Obj RefId="885">
    <TNRef RefId="0" />
    <MS>
      <S N="uuid">f73bd9e3-5d4a-42b7-b1f6-2a83e5c91230</S>
      <S N="bambooId">1234</S>
      <S N="employeeId">5678</S>
      <S N="firstName">Ivan</S>
      <S N="lastName">Novak</S>
      <S N="status">Active</S>
      <S N="gender">Male</S>
      <S N="workPhone"></S>
      <S N="workPhoneExtension"></S>
      <S N="additionalPhone"></S>
      <S N="email">ivan.novak@fictitiouscorp.com</S>
      <B N="isSlt">false</B>
      <B N="isManager">false</B>
      <B N="isTeamLead">false</B>
      <B N="isGraduate">false</B>
      <S N="employmentType">Employee</S>
      <Nil N="terminationType" />
      <Nil N="terminationDate" />
      <S N="location">Germany, Remote</S>
      <S N="department">Technical Support</S>
      <S N="division">Customer Service</S>
      <S N="jobTitle">Technical Support Specialist</S>
      <S N="managerEmail">marta.bergman@fictitiouscorp.com</S>
      <S N="grade">Mid-Level</S>
      <S N="costCentar">920 - Technical Support</S>
      <S N="entity">FictitiousCorp GmbH</S>
    </MS>
  </Obj>
